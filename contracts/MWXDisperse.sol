// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title MWXDisperse
 * @author MWX Team
 * @notice A configurable token distribution contract that splits transfers between treasury, recipients, and burn
 * @dev This contract supports both native currency (ETH) and ERC20 token distribution with configurable percentages
 */
contract MWXDisperse is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using Address for address;
    using Address for address payable;

    /// @notice Dead address used for burning tokens
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    /// @notice Maximum percentage value (100%)
    uint256 public constant MAX_PERCENTAGE = 10000; // Using basis points (100.00%)
    
    /// @notice Treasury address where treasury percentage is sent
    address public treasuryAddress;
    
    /// @notice Percentage sent to treasury (in basis points) 10000 = 100%
    uint256 public treasuryPercentage;
    
    /// @notice Percentage sent to recipients (in basis points) 10000 = 100%
    uint256 public recipientPercentage;
    
    /// @notice Percentage sent to burn address (in basis points) 10000 = 100%
    uint256 public burnPercentage;
    
    /// @notice Maximum number of recipients allowed per transaction
    uint256 public maxRecipientsPerTx;

    /// @notice Gap for future upgrades
    uint256[50] private __gap;

    /// @notice Error thrown when treasury address is invalid
    error InvalidAddress();
    /// @notice Error thrown when max recipients per transaction is invalid
    error InvalidMaxRecipientsPerTx();
    /// @notice Error thrown when percentages are invalid
    error InvalidPercentages();
    /// @notice Error thrown when no recipients are provided
    error NoRecipientsProvided();
    /// @notice Error thrown when too many recipients are provided
    error TooManyRecipients();
    /// @notice Error thrown when arrays length mismatch
    error ArraysLengthMismatch();
    /// @notice Error thrown when amount is invalid
    error InvalidAmount();
    /// @notice Error thrown when ETH transfer fails
    error ETHTransferFailed();
    /// @notice Error thrown when insufficient balance
    error InsufficientBalance();

    /**
     * @notice Emitted when tokens are dispersed
     * @param sender Address that initiated the dispersion
     * @param token Token address (0x0 for native currency)
     * @param totalAmount Total amount dispersed
     * @param recipientCount Number of recipients
     */
    event Dispersed(address indexed sender, address indexed token, uint256 totalAmount, uint256 recipientCount);

    /**
     * @notice Emitted when treasury address is updated
     * @param oldTreasury Previous treasury address
     * @param newTreasury New treasury address
     */
    event TreasuryAddressChanged(address indexed oldTreasury, address indexed newTreasury);

    /**
     * @notice Emitted when percentage configuration is updated
     * @param treasuryPercentage New treasury percentage
     * @param recipientPercentage New recipient percentage
     * @param burnPercentage New burn percentage
     */
    event PercentagesChanged(uint256 treasuryPercentage, uint256 recipientPercentage, uint256 burnPercentage);

    /**
     * @notice Emitted when max recipients per transaction is updated
     * @param oldLimit Previous limit
     * @param newLimit New limit
     */
    event MaxRecipientsChanged(uint256 oldLimit, uint256 newLimit);

    /**
     * @notice Emitted when ETH is transferred
     * @param sender Address that initiated the transfer
     * @param recipient Address that received the ETH
     * @param amount Amount of ETH transferred
     */
    event ETHTransfer(address indexed sender, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted for each individual transfer during dispersion
     * @param recipient Address that received tokens
     * @param token Token address
     * @param amount Amount received by recipient
     * @param treasuryAmount Amount sent to treasury
     * @param burnAmount Amount sent to burn address
     */
    event TokenTransfer(address indexed recipient, address indexed token, uint256 amount, uint256 treasuryAmount, uint256 burnAmount);

    /**
     * @notice Emitted when foreign token is withdrawn
     * @param token Token address
     * @param recipient Address that received the tokens
     * @param amount Amount of tokens withdrawn
     */
    event WithdrawForeignToken(address indexed token, address indexed recipient, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {}

    /**
     * @dev Required by UUPSUpgradeable
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Initializes the contract with default configuration
     * @param _initialOwner Initial owner address
     * @param _treasuryAddress Initial treasury address
     * @param _treasuryPercentage Initial treasury percentage (basis points)
     * @param _recipientPercentage Initial recipient percentage (basis points)
     * @param _burnPercentage Initial burn percentage (basis points)
     * @param _maxRecipientsPerTx Initial max recipients per transaction
     */
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(
        address _initialOwner,
        address _treasuryAddress,
        uint256 _treasuryPercentage,
        uint256 _recipientPercentage,
        uint256 _burnPercentage,
        uint256 _maxRecipientsPerTx
    ) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _setTreasuryAddress(_treasuryAddress);
        _setMaxRecipientsPerTx(_maxRecipientsPerTx);
        _setPercentages(_treasuryPercentage, _recipientPercentage, _burnPercentage);
    }

    /**
     * @notice Disperses tokens to multiple recipients with configured percentage splits
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to distribute to each recipient (before percentage splits)
     * @param token Token address (0x0 for native currency, otherwise ERC20 token address)
     * @dev Each amount[i] will be split according to configured percentages:
     *      - Treasury gets treasuryPercentage of amount[i]
     *      - Recipient gets recipientPercentage of amount[i]  
     *      - Burn address gets burnPercentage of amount[i]
     */
    function disperse(address[] calldata recipients, uint256[] calldata amounts, address token) external virtual payable nonReentrant {
        if (recipients.length == 0) revert NoRecipientsProvided();
        if (recipients.length > maxRecipientsPerTx) revert TooManyRecipients();
        if (recipients.length != amounts.length) revert ArraysLengthMismatch();

        uint256 totalAmount = 0;
        IERC20Metadata erc20Token;

        // Validate inputs
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidAddress();
            if (amounts[i] == 0) revert InvalidAmount();

            // Accumulate total amount
            totalAmount += amounts[i];
        }

        if (token == address(0)) {
            if (msg.value < totalAmount) revert InsufficientBalance();
            emit ETHTransfer(_msgSender(), address(this), totalAmount);
        } else {
            erc20Token = IERC20Metadata(token);
            uint256 senderBalance = erc20Token.balanceOf(_msgSender());
            uint256 contractAllowance = erc20Token.allowance(_msgSender(), address(this));
            if (senderBalance < totalAmount) {
                revert IERC20Errors.ERC20InsufficientBalance(_msgSender(), senderBalance, totalAmount);
            }
            if (contractAllowance < totalAmount) {
                revert IERC20Errors.ERC20InsufficientAllowance(address(this), contractAllowance, totalAmount);
            }

            erc20Token.safeTransferFrom(_msgSender(), address(this), totalAmount);
        }

        (uint256 totalTreasuryAmount, , uint256 totalBurnAmount) = _calculateSplits(totalAmount);

        if (totalTreasuryAmount > 0) {
            if (token == address(0)) {
                _safeTransferETH(address(this), treasuryAddress, totalTreasuryAmount);
            } else {
                erc20Token.safeTransfer(treasuryAddress, totalTreasuryAmount);
            }
        }

        if (totalBurnAmount > 0) {
            if (token == address(0)) {
                _safeTransferETH(address(this), treasuryAddress, totalBurnAmount);
            } else {
                erc20Token.safeTransfer(BURN_ADDRESS, totalBurnAmount);
            }
        }

        for (uint256 i = 0; i < recipients.length; i++) {
            (uint256 treasuryAmount, uint256 recipientAmount, uint256 burnAmount) = _calculateSplits(amounts[i]);
            if (recipientAmount > 0) {
                if (token == address(0)) {
                    _safeTransferETH(address(this), recipients[i], recipientAmount);
                } else {
                    erc20Token.safeTransfer(recipients[i], recipientAmount);
                }
            }

            if (token == address(0)) {
                treasuryAmount += burnAmount;
                burnAmount = 0;
            }

            emit TokenTransfer(recipients[i], token, recipientAmount, treasuryAmount, burnAmount);
        }

        if (token == address(0) && (msg.value - totalAmount) > 0) {
            _safeTransferETH(address(this), _msgSender(), msg.value - totalAmount);
        }

        emit Dispersed(_msgSender(), token, totalAmount, recipients.length);
    }

    /**
     * @notice Disperses tokens to a single recipient with configured percentage splits
     * @param recipient Recipient address
     * @param amount Amount to distribute to recipient (before percentage splits)
     * @param token Token address (0x0 for native currency, otherwise ERC20 token address)
     * @dev Amount will be split according to configured percentages:
     *      - Treasury gets treasuryPercentage of amount    
     *      - Recipient gets recipientPercentage of amount  
     *      - Burn address gets burnPercentage of amount
     */
    function disperseOne(address recipient, uint256 amount, address token) external virtual payable nonReentrant {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        
        (uint256 treasuryAmount, uint256 recipientAmount, uint256 burnAmount) = _calculateSplits(amount);

        if (token == address(0)) {
            if (msg.value < amount) revert InsufficientBalance();
            emit ETHTransfer(_msgSender(), address(this), amount);
            if (treasuryAmount > 0) _safeTransferETH(address(this), treasuryAddress, treasuryAmount);
            if (burnAmount > 0) _safeTransferETH(address(this), treasuryAddress, burnAmount);
            if (recipientAmount > 0) _safeTransferETH(address(this), recipient, recipientAmount);
        } else {
            IERC20Metadata erc20Token = IERC20Metadata(token);
            uint256 senderBalance = erc20Token.balanceOf(_msgSender());
            uint256 contractAllowance = erc20Token.allowance(_msgSender(), address(this));
            if (senderBalance < amount) {
                revert IERC20Errors.ERC20InsufficientBalance(_msgSender(), senderBalance, amount);
            }
            if (contractAllowance < amount) {
                revert IERC20Errors.ERC20InsufficientAllowance(address(this), contractAllowance, amount);
            }

            erc20Token.safeTransferFrom(_msgSender(), address(this), amount);
            if (treasuryAmount > 0) erc20Token.safeTransfer(treasuryAddress, treasuryAmount);
            if (burnAmount > 0) erc20Token.safeTransfer(BURN_ADDRESS, burnAmount);
            if (recipientAmount > 0) erc20Token.safeTransfer(recipient, recipientAmount);
        }

        if (token == address(0)) {
            if ((msg.value - amount) > 0) {
                _safeTransferETH(address(this), _msgSender(), msg.value - amount);
            }

            treasuryAmount += burnAmount;
            burnAmount = 0;
        }

        emit TokenTransfer(recipient, token, recipientAmount, treasuryAmount, burnAmount);
        emit Dispersed(_msgSender(), token, amount, 1);
    }

    /**
     * @notice Updates the treasury address
     * @param _newTreasuryAddress New treasury address
     */
    function setTreasuryAddress(address _newTreasuryAddress) external virtual onlyOwner {
        _setTreasuryAddress(_newTreasuryAddress);
    }

    /**
     * @dev Internal function to set the treasury address
     * @param _newTreasuryAddress New treasury address
     */
    function _setTreasuryAddress(address _newTreasuryAddress) internal virtual {
        if (_newTreasuryAddress == address(0)) revert InvalidAddress();
        
        address oldTreasury = treasuryAddress;
        treasuryAddress = _newTreasuryAddress;
        
        emit TreasuryAddressChanged(oldTreasury, _newTreasuryAddress);
    }

    /**
     * @notice Updates the percentage configuration
     * @param _treasuryPercentage New treasury percentage (basis points)
     * @param _recipientPercentage New recipient percentage (basis points)
     * @param _burnPercentage New burn percentage (basis points)
     */
    function setPercentages(
        uint256 _treasuryPercentage, 
        uint256 _recipientPercentage, 
        uint256 _burnPercentage
    ) external virtual onlyOwner {
        _setPercentages(_treasuryPercentage, _recipientPercentage, _burnPercentage);
    }

    /**
     * @dev Internal function to set the percentage configuration
     * @param _treasuryPercentage New treasury percentage (basis points)
     * @param _recipientPercentage New recipient percentage (basis points)
     * @param _burnPercentage New burn percentage (basis points)
     */
    function _setPercentages(
        uint256 _treasuryPercentage,
        uint256 _recipientPercentage,
        uint256 _burnPercentage
    ) internal virtual {
        if (_treasuryPercentage + _recipientPercentage + _burnPercentage != MAX_PERCENTAGE) revert InvalidPercentages();

        treasuryPercentage = _treasuryPercentage;
        recipientPercentage = _recipientPercentage;
        burnPercentage = _burnPercentage;

        emit PercentagesChanged(_treasuryPercentage, _recipientPercentage, _burnPercentage);
    }

    /**
     * @notice Updates the maximum recipients per transaction limit
     * @param _maxRecipientsPerTx New maximum recipients per transaction
     */
    function setMaxRecipientsPerTx(uint256 _maxRecipientsPerTx) external virtual onlyOwner {
        _setMaxRecipientsPerTx(_maxRecipientsPerTx);
    }

    /**
     * @dev Internal function to set the maximum recipients per transaction limit
     * @param _maxRecipientsPerTx New maximum recipients per transaction
     */
    function _setMaxRecipientsPerTx(uint256 _maxRecipientsPerTx) internal virtual {
        if (_maxRecipientsPerTx == 0) revert InvalidMaxRecipientsPerTx();
        
        uint256 oldLimit = maxRecipientsPerTx;
        maxRecipientsPerTx = _maxRecipientsPerTx;
        
        emit MaxRecipientsChanged(oldLimit, _maxRecipientsPerTx);
    }

    /**
     * @dev Withdraws foreign tokens to specified address
     * @param _token Address of the token to withdraw
     * @param _recipient Address to send the tokens to
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawForeignToken(address _token, address _recipient, uint256 _amount) external virtual onlyOwner {
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
     * @notice Gets the current configuration
     * @return _treasuryAddress Treasury address
     * @return _treasuryPercentage Treasury percentage
     * @return _recipientPercentage Recipient percentage
     * @return _burnPercentage Burn percentage
     * @return _maxRecipientsPerTx Maximum recipients per transaction
     */
    function getConfiguration() external virtual view returns (
        address _treasuryAddress,
        uint256 _treasuryPercentage,
        uint256 _recipientPercentage,
        uint256 _burnPercentage,
        uint256 _maxRecipientsPerTx
    ) {
        return (
            treasuryAddress,
            treasuryPercentage,
            recipientPercentage,
            burnPercentage,
            maxRecipientsPerTx
        );
    }

    /**
     * @notice Calculates split amounts for a given total
     * @param totalAmount Total amount to split
     * @return treasuryAmount Amount for treasury
     * @return recipientAmount Amount for recipient
     * @return burnAmount Amount for burn
     */
    function calculateSplits(uint256 totalAmount) external virtual view returns (
        uint256 treasuryAmount,
        uint256 recipientAmount,
        uint256 burnAmount
    ) {
        return _calculateSplits(totalAmount);
    }

    /**
     * @dev Internal function to calculate percentage splits
     * @param totalAmount Total amount to split
     * @return treasuryAmount Amount for treasury
     * @return recipientAmount Amount for recipient
     * @return burnAmount Amount for burn
     */
    function _calculateSplits(uint256 totalAmount) internal virtual view returns (
        uint256 treasuryAmount,
        uint256 recipientAmount,
        uint256 burnAmount
    ) {
        treasuryAmount = (totalAmount * treasuryPercentage) / MAX_PERCENTAGE;
        recipientAmount = (totalAmount * recipientPercentage) / MAX_PERCENTAGE;
        burnAmount = (totalAmount * burnPercentage) / MAX_PERCENTAGE;
    }

    /**
     * @dev Safe ETH transfer function
     * @param from Address to send the ETH from
     * @param to Address to send the ETH to
     * @param amount Amount of ETH to send
     */
    function _safeTransferETH(address from, address to, uint256 amount) internal virtual {
        (bool success, ) = to.call{value: amount}("");

        if (!success) revert ETHTransferFailed();

        emit ETHTransfer(from, to, amount);
    }
}