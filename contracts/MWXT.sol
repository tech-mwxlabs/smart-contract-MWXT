// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol';
import '@openzeppelin/contracts/utils/Address.sol';

/**
 * @title MWXT
 * @author MWX Team
 * @notice MWXT is the native token of the MWX ecosystem.
 * @dev ERC20 token with the following features:
 * - Upgradeable using UUPS proxy pattern
 * - Burnable tokens
 * - EIP-2612 permit functionality
 * - Ownable with access control
 * - Pausable transfers
 * - Withdrawal of foreign tokens
 */
contract MWXT is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PermitUpgradeable, ERC20PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using Address for address;
    using Address for address payable;

    event WithdrawForeignToken(address token, address recipient, uint256 amount);

    error InsufficientBalance();
    error InvalidAddress();
    error InvalidAmount();

    /// @notice Gap for future upgrades
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with token details
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial supply to mint to owner
     * @param initialOwner Initial owner of the contract
     */
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(string memory name, string memory symbol, uint256 initialSupply, address initialOwner) public initializer {
        if (initialOwner == address(0)) revert InvalidAddress();

        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __Ownable_init(initialOwner);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __UUPSUpgradeable_init();

        _mint(initialOwner, initialSupply * 10 ** decimals());
    }

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
     * @dev Pauses token transfers
     */
    function pause() public virtual onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses token transfers
     */
    function unpause() public virtual onlyOwner {
        _unpause();
    }

    /**
     * @dev Authorizes upgrade to new implementation
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Hook that is called before any transfer of tokens
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) whenNotPaused {
        super._update(from, to, value);
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
}