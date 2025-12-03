// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title MWXLaunchpad
 * @author MWX Team
 * @notice A launchpad contract for private sale of MWXT tokens with whitelist verification
 * @dev Implements UUPS proxy pattern with comprehensive access controls and security features
 */
contract MWXLaunchpad is Initializable, UUPSUpgradeable, OwnableUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, EIP712Upgradeable {
    using SafeERC20 for IERC20Metadata;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using Address for address;
    using Address for address payable;

    struct UserContribution {
        address paymentToken;
        uint256 usdAmount;
        uint256 tokenAmount;
        uint256 totalUSDContributedBefore;
        uint256 totalUSDContributedAfter;
        uint256 totalTokenAllocatedBefore;
        uint256 totalTokenAllocatedAfter;
        uint256 timestamp;
    }

    /// @notice EIP-712 typehash for buy allocation
    bytes32 public constant BUY_ALLOCATION_TYPEHASH = keccak256("BuyAllocation(address buyer)");

    /// @notice USDT token contract
    IERC20Metadata public usdt;

    /// @notice USDC token contract
    IERC20Metadata public usdc;

    /// @notice Start time of the token sale
    uint256 public startTime;

    /// @notice End time of the token sale
    uint256 public endTime;

    /// @notice Price per token in USD (standarized to 18 decimals)
    uint256 public tokenPrice;

    /// @notice Total allocation of tokens available for sale
    uint256 public totalAllocation;

    /// @notice Soft cap amount in USD (standarized to decimals of payment token)
    uint256 public softCap;

    /// @notice Hard cap amount in USD (standarized to decimals of payment token)
    uint256 public hardCap;

    /// @notice Minimum purchase amount in USD (standarized to decimals of payment token)
    uint256 public minimumPurchase;

    /// @notice Destination address to receive collected funds
    address public destinationAddress;

    /// @notice Admin verifier address for signature verification
    address public adminVerifier;

    /// @notice Decimal of the token sold
    uint8 public decimalTokenSold;

    /// @notice Total USDT amount collected
    uint256 public totalUsdtCollected;

    /// @notice Total USDC amount collected
    uint256 public totalUsdcCollected;

    /// @notice Total tokens sold
    uint256 public totalTokensSold;

    /// @notice Whether the sale has ended
    bool public saleEnded;

    /// @notice Whether funds have been withdrawn
    bool public fundsWithdrawn;

    /// @notice Array of user addresses
    address[] public userContributors;

    /// @notice Array of user addresses that have been refunded
    address[] public userRefunded;

    /// @notice Total User that contributed to the sale
    uint256 public totalUserContributed;

    /// @notice Total User that have been refunded
    uint256 public totalUserRefunded;

    /// @notice Mapping of user address to their USD contribution
    mapping(address => uint256) public userContributions;

    /// @notice Mapping of user address to their USDC contribution
    mapping(address => uint256) public userUsdcContributions;

    /// @notice Mapping of user address to their USDT contribution
    mapping(address => uint256) public userUsdtContributions;

    /// @notice Mapping of user address to their token allocation
    mapping(address => uint256) public userAllocations;

    /// @notice Mapping to track refund claims
    mapping(address => uint256) public refundClaimed;

    /// @notice Mapping of user address to their contribution details
    mapping(address => UserContribution[]) public userContributionDetail;

    /// @notice Gap for future upgrades
    uint256[50] private __gap;

    /**
     * @notice Emitted when a sale is started
     * @param startTime The start time of the sale
     * @param endTime The end time of the sale
     * @param tokenPrice The price per token (standarized to 18 decimals)
     * @param totalAllocation The total allocation of tokens (standarized to decimals of token sold)
     * @param decimalTokenSold The decimal of the token sold
     */
    event SaleStarted(uint256 startTime, uint256 endTime, uint256 tokenPrice, uint256 totalAllocation, uint8 decimalTokenSold);

    /**
     * @notice Emitted when an allocation is purchased
     * @param buyer The address of the buyer
     * @param usdAmount The amount of USD paid (standarized to decimals of payment token)
     * @param tokenAmount The amount of tokens allocated (standarized to decimals of token sold)
     * @param currentTimestamp The timestamp of the purchase
     */
    event AllocationPurchased(address indexed buyer, uint256 usdAmount, uint256 tokenAmount, uint256 currentTimestamp);

    /**
     * @notice Emitted when USD is transferred to destination (real-time transfer)
     * @param amount The amount transferred (standarized to decimals of payment token)
     * @param destinationAddress The destination address
     */
    event USDTransferredToDestination(uint256 amount, address indexed destinationAddress);

    /**
     * @notice Emitted when USD is withdrawn
     * @param amount The amount withdrawn (standarized to decimals of payment token)
     * @param destinationAddress The destination address
     */
    event USDWithdrawn(uint256 amount, address indexed destinationAddress);

    /**
     * @notice Emitted when the sale ends
     * @param endTime The end time of the sale
     * @param totalUSDCollected The total USD collected (standarized to decimals of payment token)
     * @param totalTokensSold The total tokens sold (standarized to decimals of token sold)
     */
    event SaleEnded(uint256 endTime, uint256 totalUSDCollected, uint256 totalTokensSold);

    /**
     * @notice Emitted when a refund is issued
     * @param buyer The address of the buyer receiving refund
     * @param usdAmount The amount refunded (standarized to decimals of payment token)
     */
    event RefundIssued(address indexed buyer, uint256 usdAmount);

    /**
     * @notice Emitted when a sale is updated
     * @param endTime The end time of the sale
     * @param minimumPurchase The minimum purchase amount (standarized to decimals of payment token)
     */
    event SaleUpdated(uint256 endTime, uint256 minimumPurchase);

    /**
     * @notice Emitted when a foreign token is withdrawn
     * @param token The address of the token 0x0000000000000000000000000000000000000000 for native token
     * @param recipient The address of the recipient
     * @param amount The amount of tokens withdrawn
     */
    event WithdrawForeignToken(address token, address recipient, uint256 amount);

    /**
     * @notice Emitted when the admin verifier address is updated
     * @param oldAdminVerifier The old admin verifier address
     * @param newAdminVerifier The new admin verifier address
     */
    event AdminVerifierUpdated(address oldAdminVerifier, address newAdminVerifier);
    
    /**
     * @notice Emitted when the destination address is updated
     * @param oldDestinationAddress The old destination address
     * @param newDestinationAddress The new destination address
     */
    event DestinationAddressUpdated(address oldDestinationAddress, address newDestinationAddress);
    
    /**
     * @notice Emitted when the USDT address is updated
     * @param oldUsdt The old USDT address
     * @param newUsdt The new USDT address
     */
    event UsdtAddressUpdated(address oldUsdt, address newUsdt);
    
    /**
     * @notice Emitted when the USDC address is updated
     * @param oldUsdc The old USDC address
     * @param newUsdc The new USDC address
     */
    event UsdcAddressUpdated(address oldUsdc, address newUsdc);

    /**
     * @notice Emitted when the decimal of the token sold is updated
     * @param oldDecimalTokenSold The old decimal of the token sold
     * @param newDecimalTokenSold The new decimal of the token sold
     */
    event DecimalTokenSoldUpdated(uint8 oldDecimalTokenSold, uint8 newDecimalTokenSold);

    error SaleNotActive();
    error SaleAlreadyStarted();
    error SaleAlreadyEnded();
    error SaleNotEnded();
    error TotalAllocationExceeded();
    error BelowMinimumPurchase();
    error ExceedsHardCap();
    error InsufficientBalance();
    error InsufficientAllowance();
    error InvalidSignature();
    error SoftCapNotReached();
    error SoftCapReached();
    error FundsAlreadyWithdrawn();
    error RefundAlreadyClaimed();
    error InvalidPaymentToken();
    error InvalidAmount();  
    error InvalidTimeRange();
    error InvalidAddress();
    error InvalidTokenAddress();
    error NoUserContribution();
    error InvalidHash();
    error RoleAlreadyExists();
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the launchpad contract
     * @param _usdt USDT token contract address
     * @param _usdc USDC token contract address
     * @param _owner Owner address
     * @param _adminVerifier Admin verifier address
     * @param _destinationAddress Destination address for funds
     */
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(address _usdt, address _usdc, address _owner, address _adminVerifier, address _destinationAddress, uint8 _decimalTokenSold) public initializer {
        if (_usdt == address(0) || _usdc == address(0)) revert InvalidTokenAddress();
        if (_owner == address(0) || _adminVerifier == address(0) || _destinationAddress == address(0)) revert InvalidAddress();

        __Ownable_init(_owner);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __EIP712_init("MWXLaunchpad", "1");

        usdt = IERC20Metadata(_usdt);
        usdc = IERC20Metadata(_usdc);
        adminVerifier = _adminVerifier;
        destinationAddress = _destinationAddress;
        decimalTokenSold = _decimalTokenSold;

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    /**
     * @dev Authorizes contract upgrades (UUPS pattern)
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Receive function to receive native tokens
     */
    receive() external virtual payable {}

    /**
     * @dev Returns the current implementation version
     */
    function version() public view virtual returns (string memory) {
        return _EIP712Version();
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Configures the sale parameters
     * @param _startTime Start time of the sale
     * @param _endTime End time of the sale
     * @param _tokenPrice Price per token in USD (standarized to 18 decimals)
     * @param _totalAllocation Total allocation of tokens (standarized to decimals of token sold)
     * @param _softCap Soft cap amount in USD (standarized to decimals of payment token)
     * @param _hardCap Hard cap amount in USD (standarized to decimals of payment token)
     * @param _minimumPurchase Minimum purchase amount in USD (standarized to decimals of payment token)
     * @param _decimalTokenSold Decimal of the token sold
     */
    function configureSale(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _tokenPrice,
        uint256 _totalAllocation,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _minimumPurchase,
        uint8 _decimalTokenSold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_startTime >= _endTime || _startTime < block.timestamp) revert InvalidTimeRange();
        if (_tokenPrice == 0 || _totalAllocation == 0 || _softCap == 0 || _hardCap == 0 || _minimumPurchase == 0) revert InvalidAmount();
        if (_softCap >= _hardCap) revert InvalidAmount();
        if (startTime > 0 && block.timestamp >= startTime) revert SaleAlreadyStarted();

        startTime = _startTime;
        endTime = _endTime;
        tokenPrice = _tokenPrice;
        totalAllocation = _totalAllocation;
        softCap = _softCap;
        hardCap = _hardCap;
        minimumPurchase = _minimumPurchase;
        decimalTokenSold = _decimalTokenSold;

        emit SaleStarted(_startTime, _endTime, _tokenPrice, _totalAllocation, _decimalTokenSold);
    }

    /**
     * @notice Returns the total USD collected
     * @return totalUSDCollected The total USD collected
     */
    function totalUSDCollected() public view returns (uint256) {
        return totalUsdtCollected + totalUsdcCollected;
    }

    /**
     * @dev Updates the sale parameters
     * @param _endTime End time of the sale
     * @param _minimumPurchase Minimum purchase amount in USD (standarized to decimals of payment token)
     */
    function setSaleParameters(uint256 _endTime, uint256 _minimumPurchase) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_endTime <= startTime) revert InvalidTimeRange();
        if (_endTime <= block.timestamp) revert InvalidTimeRange();
        if (_minimumPurchase == 0) revert InvalidAmount();

        endTime = _endTime;
        minimumPurchase = _minimumPurchase;

        emit SaleUpdated(endTime, minimumPurchase);
    }

    /**
     * @notice Allows whitelisted users to buy token allocation
     * @param buyer Address of the buyer
     * @param usdAmount Amount of USD to spend (standarized to decimals of payment token)
     * @param paymentToken Address of the payment token
     * @param signature Signature from admin verifier
     */
    function buyAllocation(address buyer, address paymentToken, uint256 usdAmount, bytes calldata signature) external virtual nonReentrant whenNotPaused {
        if (block.timestamp < startTime) revert SaleNotActive();
        if (block.timestamp >= endTime) revert SaleAlreadyEnded();
        if (saleEnded) revert SaleAlreadyEnded();
        if (usdAmount < minimumPurchase) revert BelowMinimumPurchase();
        if (totalUSDCollected() + usdAmount > hardCap) revert ExceedsHardCap();
        if (paymentToken != address(usdt) && paymentToken != address(usdc)) revert InvalidPaymentToken();

        if (buyer == address(0)) {
            buyer = _msgSender();
        }

        // Verify whitelist signature
        bytes32 structHash = keccak256(abi.encode(BUY_ALLOCATION_TYPEHASH, buyer));
        bytes32 hash = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(adminVerifier, hash, signature)) {
            revert InvalidSignature();
        }
        
        if (IERC20Metadata(paymentToken).balanceOf(_msgSender()) < usdAmount) revert InsufficientBalance();
        if (IERC20Metadata(paymentToken).allowance(_msgSender(), address(this)) < usdAmount) revert InsufficientAllowance();

        uint256 tokenAmount = getTokenAmountOut(paymentToken, usdAmount);

        if (totalTokensSold + tokenAmount > totalAllocation) revert TotalAllocationExceeded();

        // Transfer USD tokens
        IERC20Metadata(paymentToken).safeTransferFrom(_msgSender(), address(this), usdAmount);

        userContributionDetail[buyer].push(UserContribution({
            paymentToken: paymentToken,
            usdAmount: usdAmount,
            tokenAmount: tokenAmount,
            totalUSDContributedBefore: userContributions[buyer],
            totalUSDContributedAfter: userContributions[buyer] + usdAmount,
            totalTokenAllocatedBefore: userAllocations[buyer],
            totalTokenAllocatedAfter: userAllocations[buyer] + tokenAmount,
            timestamp: block.timestamp
        }));

        // Update sale information
        if (paymentToken == address(usdt)) {
            totalUsdtCollected += usdAmount;
            userUsdtContributions[buyer] += usdAmount;
        } else {
            totalUsdcCollected += usdAmount;
            userUsdcContributions[buyer] += usdAmount;
        }

        if (userContributions[buyer] == 0) {
            userContributors.push(buyer);
            totalUserContributed++;
        }

        userContributions[buyer] += usdAmount;
        userAllocations[buyer] += tokenAmount;
        totalTokensSold += tokenAmount;

        emit AllocationPurchased(buyer, usdAmount, tokenAmount, block.timestamp);

        // Check if hard cap reached
        if (totalUSDCollected() >= hardCap) {
            _endSale();
        }
    }
    
    
    /**
     * @notice Withdraws collected funds to destination address
     * @dev Can only be called if soft cap is reached and sale has ended
     */
    function withdrawFunds() external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!saleEnded && block.timestamp < endTime) revert SaleNotEnded();
        if (totalUSDCollected() < softCap) revert SoftCapNotReached();
        if (fundsWithdrawn) revert FundsAlreadyWithdrawn();

        if (!saleEnded) {
            _endSale();
        }

        fundsWithdrawn = true;

        uint256 _totalUSDCollected = totalUSDCollected();

        // Transfer USDT balance
        if (usdt.balanceOf(address(this)) > 0) {
            usdt.safeTransfer(destinationAddress, totalUsdtCollected);
        }

        // Transfer USDC balance
        if (usdc.balanceOf(address(this)) > 0) {
            usdc.safeTransfer(destinationAddress, totalUsdcCollected);
        }

        emit USDWithdrawn(_totalUSDCollected, destinationAddress);
    }

    /**
     * @notice Allows users to claim refund if soft cap is not reached
     */
    function claimRefund() external virtual {
        _processRefund(_msgSender());
    }

    /**
     * @dev Allows admin to process refund for a user
     * @param user Address of the user to refund
     */
    function claimRefundForUser(address user) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _processRefund(user);
    }

    /**
     * @dev Internal function to process refunds
     * @param user Address of the user to refund
     */
    function _processRefund(address user) internal virtual nonReentrant whenNotPaused {
        if (!saleEnded && block.timestamp < endTime) revert SaleNotEnded();
        if (totalUSDCollected() >= softCap) revert SoftCapReached();
        if (refundClaimed[user] > 0) revert RefundAlreadyClaimed();
        
        uint256 refundAmount = userContributions[user];
        if (refundAmount == 0) revert NoUserContribution();

        if (!saleEnded) {
            _endSale();
        }

        // Calculate USDT and USDC proportions based on contract balance
        uint256 usdtBalance = usdt.balanceOf(address(this));
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 totalBalance = usdtBalance + usdcBalance;

        if (totalBalance == 0 || totalBalance < refundAmount) revert InsufficientBalance();

        refundClaimed[user] = refundAmount;

        uint256 usdtRefund = userUsdtContributions[user];
        uint256 usdcRefund = userUsdcContributions[user];

        if (usdtRefund > 0 && usdtRefund <= usdtBalance) {
            usdt.safeTransfer(user, usdtRefund);
        }
        if (usdcRefund > 0 && usdcRefund <= usdcBalance) {
            usdc.safeTransfer(user, usdcRefund);
        }

        userRefunded.push(user);
        totalUserRefunded++;

        emit RefundIssued(user, refundAmount);
    }

    /**
     * @dev Ends the sale manually
     */
    function endSale() external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (saleEnded) revert SaleAlreadyEnded();
        _endSale();
    }

    /**
     * @dev Internal function to end the sale
     */
    function _endSale() internal virtual {
        saleEnded = true;
        emit SaleEnded(block.timestamp, totalUSDCollected(), totalTokensSold);
    }

    function setDecimalTokenSold(uint8 _decimalTokenSold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (block.timestamp >= startTime || totalUserContributed > 0) revert SaleAlreadyStarted();
        
        uint8 oldDecimalTokenSold = decimalTokenSold;
        decimalTokenSold = _decimalTokenSold;

        emit DecimalTokenSoldUpdated(oldDecimalTokenSold, decimalTokenSold);
    }

    /**
     * @dev Updates the admin verifier address
     * @param _adminVerifier New admin verifier address
     */
    function setAdminVerifier(address _adminVerifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_adminVerifier == address(0)) revert InvalidAddress();
        address oldAdminVerifier = adminVerifier;
        adminVerifier = _adminVerifier;

        emit AdminVerifierUpdated(oldAdminVerifier, _adminVerifier);
    }

    /**
     * @dev Updates the destination address
     * @param _destinationAddress New destination address
     */
    function setDestinationAddress(address _destinationAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_destinationAddress == address(0)) revert InvalidAddress();
        address oldDestinationAddress = destinationAddress;
        destinationAddress = _destinationAddress;
        
        emit DestinationAddressUpdated(oldDestinationAddress, _destinationAddress);
    }

    /**
     * @dev Updates the USDT address
     * @param _usdt New USDT address
     */
    function setUsdtAddress(IERC20Metadata _usdt) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(_usdt) == address(0)) revert InvalidAddress();
        address oldUsdt = address(usdt);
        usdt = _usdt;
        
        emit UsdtAddressUpdated(oldUsdt, address(_usdt));
    }

    /**
     * @dev Updates the USDC address
     * @param _usdc New USDC address
     */
    function setUsdcAddress(IERC20Metadata _usdc) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(_usdc) == address(0)) revert InvalidAddress();
        address oldUsdc = address(usdc);
        usdc = _usdc;
        
        emit UsdcAddressUpdated(oldUsdc, address(_usdc));
    }

    /**
     * @notice Returns the token amount out for a given USD amount (in decimals of token sold)
     * @param paymentToken Address of the payment token
     * @param usdAmount Amount of USD to spend (decimals of payment token)
     * @return tokenAmount Amount of tokens to receive (decimals of token sold)
     */
    function getTokenAmountOut(address paymentToken, uint256 usdAmount) public virtual view returns (uint256) {
        if (paymentToken != address(usdt) && paymentToken != address(usdc)) revert InvalidPaymentToken();
        if (usdAmount == 0) revert InvalidAmount();
        
        uint256 adjustedUsdAmount = usdAmount * 10 ** (18 - IERC20Metadata(paymentToken).decimals()); // Adjust USD amount to 18 decimals
        uint256 tokenAmount = (adjustedUsdAmount * 10 ** decimalTokenSold) / tokenPrice; // token price is in 18 decimals

        return tokenAmount;
    }

    /**
     * @notice Returns the current sale status
     * @return isActive Whether the sale is currently active
     * @return isEnded Whether the sale has ended
     * @return softCapReached Whether soft cap has been reached
     * @return hardCapReached Whether hard cap has been reached
     */
    function getSaleStatus() external view returns (bool isActive, bool isEnded, bool softCapReached, bool hardCapReached) {
        isActive = !saleEnded && block.timestamp >= startTime && block.timestamp <= endTime;
        isEnded = saleEnded || block.timestamp > endTime;
        softCapReached = totalUSDCollected() >= softCap;
        hardCapReached = totalUSDCollected() >= hardCap;
    }

    /**
     * @notice Returns user's contribution and allocation information
     * @param user Address of the user
     * @return contribution User's USD contribution
     * @return usdtContribution User's USDT contribution
     * @return usdcContribution User's USDC contribution
     * @return allocation User's token allocation
     * @return refundedAmount User's refunded amount
     * @return totalContributionHistory Total number of contribution history
     * @return canClaimRefund Whether user can claim refund
     */
    function getUserInfo(address user) external virtual view returns (uint256 contribution, uint256 usdtContribution, uint256 usdcContribution, uint256 allocation, uint256 refundedAmount, uint256 totalContributionHistory, bool canClaimRefund) {
        contribution = userContributions[user];
        usdtContribution = userUsdtContributions[user];
        usdcContribution = userUsdcContributions[user];
        allocation = userAllocations[user];
        refundedAmount = refundClaimed[user];
        totalContributionHistory = userContributionDetail[user].length;
        canClaimRefund = refundedAmount == 0 && contribution > 0 && (saleEnded || block.timestamp > endTime) && totalUSDCollected() < softCap;
    }

    /**
     * @dev Withdraws foreign tokens to specified address
     * @param _token Address of the token to withdraw
     * @param _recipient Address to send the tokens to
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawForeignToken(address _token, address _recipient, uint256 _amount) external virtual onlyOwner {
        if (_token == address(usdt) || _token == address(usdc)) revert InvalidTokenAddress();
        if (_recipient == address(0)) revert InvalidAddress();
        if (_amount == 0) revert InvalidAmount();

        if (_token == address(0)) {
            if (address(this).balance < _amount) revert InsufficientBalance();
            payable(_recipient).sendValue(_amount);
        } else {
            uint256 contractBalance = uint256(IERC20Metadata(_token).balanceOf(address(this)));
            if (contractBalance < _amount) revert IERC20Errors.ERC20InsufficientBalance(address(this), contractBalance, _amount);
            IERC20Metadata(_token).safeTransfer(_recipient, _amount);
        }

        emit WithdrawForeignToken(_token, _recipient, _amount);
    }

    /**
     * @notice Returns the contributors list
     * @param offset Offset of the first item to return
     * @param limit Maximum number of items to return
     * @return result Array of user addresses
     * @return total Total number of contributors
     */
    function getUserContributors(uint256 offset, uint256 limit) external view virtual returns (address[] memory result, uint256 total) {
        total = userContributors.length;
        
        if (offset >= total) {
            return (new address[](0), total);
        }
        
        uint256 remaining = total - offset;
        uint256 actualLimit = remaining < limit ? remaining : limit;
        
        result = new address[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit; i++) {
            result[i] = userContributors[offset + i];
        }
        
        return (result, total);
    }

    /**
     * @notice Returns the user's contribution history
     * @param user Address of the user
     * @param offset Offset of the first item to return
     * @param limit Maximum number of items to return
     * @return result Array of user contributions
     * @return total Total number of user contributions
     */
    function getUserContributionHistory(address user, uint256 offset, uint256 limit) external view virtual returns (UserContribution[] memory result, uint256 total) {
        total = userContributionDetail[user].length;
        
        if (offset >= total) {
            return (new UserContribution[](0), total);
        }
        
        uint256 remaining = total - offset;
        uint256 actualLimit = remaining < limit ? remaining : limit;
        
        result = new UserContribution[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit; i++) {
            result[i] = userContributionDetail[user][offset + i];
        }
        
        return (result, total);
    }

    /**
     * @notice Returns the refunded list
     * @param offset Offset of the first item to return
     * @param limit Maximum number of items to return
     * @return result Array of user addresses
     * @return total Total number of refunded users
     */
    function getUserRefunded(uint256 offset, uint256 limit) external view virtual returns (address[] memory result, uint256 total) {
        total = userRefunded.length;
        
        if (offset >= total) {
            return (new address[](0), total);
        }
        
        uint256 remaining = total - offset;
        uint256 actualLimit = remaining < limit ? remaining : limit;
        
        result = new address[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit; i++) {
            result[i] = userRefunded[offset + i];
        }
        
        return (result, total);
    }
}