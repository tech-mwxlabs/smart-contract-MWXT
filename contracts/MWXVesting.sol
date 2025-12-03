// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title MWXVesting
 * @author MWX Team
 * @notice A token vesting contract that releases tokens linearly over time with configurable intervals
 * @dev Implements UUPS proxy pattern with comprehensive access controls and security features
 * @dev A token vesting contract that releases tokens linearly over time with configurable intervals
 */
contract MWXVesting is Initializable, UUPSUpgradeable, OwnableUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using Address for address;
    using Address for address payable;

    /// @notice Role for managing vesting schedules
    bytes32 public constant SCHEDULE_MANAGER_ROLE = keccak256("SCHEDULE_MANAGER_ROLE");

    /// @notice Role for releasing tokens
    bytes32 public constant RELEASER_ROLE = keccak256("RELEASER_ROLE");

    /**
     * @notice Emitted when a vesting schedule is created
     * @param beneficiary The beneficiary address
     * @param amount The amount of tokens vested
     * @param startTime The start timestamp of the vesting schedule
     * @param cliffDuration The cliff duration of the vesting schedule
     * @param vestingDuration The vesting duration of the vesting schedule
     * @param releaseInterval The release interval of the vesting schedule
     */
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount, uint256 startTime, uint256 cliffDuration, uint256 vestingDuration, uint256 releaseInterval);

    /**
     * @notice Emitted when a vesting schedule is revoked
     * @param beneficiary The beneficiary address
     * @param releasedAmount The amount of tokens released
     * @param unreleasedAmount The amount of tokens unreleased
     */
    event VestingScheduleRevoked(address indexed beneficiary, uint256 releasedAmount, uint256 unreleasedAmount);

    /**
     * @notice Emitted when tokens are claimed
     * @param beneficiary The beneficiary address
     * @param amount The amount of tokens claimed
     */
    event TokensClaimed(address indexed beneficiary, uint256 amount);

    /**
     * @notice Emitted when vesting parameters are set or updated
     * @param startTimestamp The start timestamp of the vesting schedule
     * @param cliffDuration The cliff duration of the vesting schedule
     * @param vestingDuration The vesting duration of the vesting schedule
     * @param releaseIntervalDays The release interval of the vesting schedule
     */
    event VestingParametersSet(uint256 startTimestamp, uint256 cliffDuration, uint256 vestingDuration, uint256 releaseIntervalDays);

    /**
     * @notice Emitted when emergency withdraw is called
     * @param admin The address of the admin
     * @param amount The amount of tokens withdrawn
     */
    event EmergencyWithdraw(address indexed admin, uint256 amount);
    /**
     * @notice Emitted when a foreign token is withdrawn
     * @param token The address of the token 0x0000000000000000000000000000000000000000 for native token
     * @param recipient The address of the recipient
     * @param amount The amount of tokens withdrawn
     */
    event WithdrawForeignToken(address token, address recipient, uint256 amount);

    /**
     * @notice Emitted when the maximum number of beneficiaries for a single batch is updated
     * @param maxBatch The new maximum number of beneficiaries
     */
    event MaxBatchForCreateVestingScheduleUpdated(uint8 maxBatch);
    
    /**
     * @notice Emitted when the maximum number of beneficiaries for a single batch is updated
     * @param maxBatch The new maximum number of beneficiaries
     */
    event MaxBatchForReleaseUpdated(uint8 maxBatch);

    /**
     * @notice Emitted when the vesting token is updated
     * @param oldVestingToken The old vesting token
     * @param newVestingToken The new vesting token
     */
    event VestingTokenUpdated(address oldVestingToken, address newVestingToken);

    error InvalidAddress();
    error InvalidTime();
    error InvalidVestingParams();
    error InvalidTimeRange();
    error InvalidParameterLength();
    error InvalidAmount();
    error InvalidSchedule();
    error InsufficientBalance();
    error ScheduleNotActive();
    error InvalidTokenAddress();
    error VestingTokenAlreadySet();
    error VestingTokenNotSet();
    error ZeroValueParameter();

    /// @notice Vesting schedule struct
    struct VestingSchedule {
        address beneficiary;        // Beneficiary address
        uint256 totalVestedAmount;  // Total tokens to be vested linearly after cliff
        uint256 releaseAmountAtCliff; // Amount released at cliff
        uint256 claimedAmount;      // Amount already claimed (including cliff)
        uint256 startTimestamp;     // When vesting starts
        uint256 cliffDuration;      // Cliff period in seconds
        uint256 vestingDuration;    // Total vesting duration in seconds (for linear vesting after cliff)
        uint256 releaseInterval;    // Release interval in seconds
        bool isActive;              // Whether the schedule is active
    }

    /// @notice Default vesting parameters struct
    struct DefaultVestingParams {
        uint256 startTimestamp;
        uint256 cliffDuration;      // in seconds
        uint256 vestingDuration;    // in seconds
        uint256 releaseIntervalDays; // in days
    }

    /// @notice Claim struct
    struct Claim {
        address beneficiary;        // Beneficiary address
        uint256 amount;             // Amount claimed
        uint256 timestamp;          // Timestamp of the claim
    }

    /// @notice Vested token contract
    IERC20Metadata public vestingToken;

    /// @notice Default vesting parameters
    DefaultVestingParams public defaultParams;
    
    /// @notice Beneficiary address => VestingSchedule
    mapping(address => VestingSchedule) public beneficiaryVestingSchedules;

    /// @notice Beneficiary address => Claim
    mapping(address => Claim[]) public beneficiaryClaims;
    
    /// @notice Track all beneficiaries for admin purposes
    address[] public beneficiaries;

    /// @notice Mapping of beneficiary addresses to their vesting schedule
    mapping(address => bool) public isBeneficiary;

    /// @notice Maximum number of beneficiaries for a single batch
    uint8 public maxBatchForCreateVestingSchedule;

    /// @notice Maximum number of beneficiaries for a single batch
    uint8 public maxBatchForRelease;

    /// @notice Total amount of tokens vested exclude cliff amount
    uint256 public totalVestedAmount;

    /// @notice Total amount of tokens vested for cliff
    uint256 public totalCliffVestedAmount;

    /// @notice Constants
    uint256 public constant SECONDS_PER_DAY = 86400;

    /// @notice Gap for future upgrades
    uint256[50] private __gap;

    /// @notice Modifier to check if the caller is a beneficiary
    modifier onlyBeneficiary() {
        if (!beneficiaryVestingSchedules[_msgSender()].isActive) revert ScheduleNotActive();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the vesting contract
     * @param _owner The owner of the contract
     * @param _scheduleManager The address that can manage the vesting schedules
     * @param _startTimestamp The start timestamp of the vesting schedule
     * @param _cliffDuration The cliff duration of the vesting schedule
     * @param _vestingDuration The vesting duration of the vesting schedule
     * @param _releaseIntervalDays The release interval of the vesting schedule
     * @param _maxBatchForCreateVestingSchedule The maximum number of beneficiaries for a single batch
     * @param _maxBatchForRelease The maximum number of beneficiaries for a single batch
     */
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(
        address _owner,  
        address _scheduleManager,
        uint8 _maxBatchForCreateVestingSchedule, 
        uint8 _maxBatchForRelease,
        DefaultVestingParams calldata _defaultParams
    ) public initializer {
        if (_owner == address(0) || _scheduleManager == address(0)) revert InvalidAddress();

        __Ownable_init(_owner);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _setVestingParameters(_defaultParams);
        _setMaxBatchForCreateVestingSchedule(_maxBatchForCreateVestingSchedule);
        _setMaxBatchForRelease(_maxBatchForRelease);

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(SCHEDULE_MANAGER_ROLE, _scheduleManager);
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
     * @dev Set default vesting parameters (only SCHEDULE_MANAGER_ROLE)
     * @param _defaultParams The default vesting parameters
     */
    function setVestingParameters(DefaultVestingParams calldata _defaultParams) external virtual onlyRole(SCHEDULE_MANAGER_ROLE) {
        _setVestingParameters(_defaultParams);
    }

    /**
     * @dev Set default vesting parameters (only SCHEDULE_MANAGER_ROLE)
     * @param _defaultParams The default vesting parameters
     */
    function _setVestingParameters(DefaultVestingParams calldata _defaultParams) internal virtual {
        if (!_isValidVestingParams(_defaultParams.startTimestamp, _defaultParams.cliffDuration, _defaultParams.vestingDuration, _defaultParams.releaseIntervalDays)) {
            revert InvalidVestingParams();
        }

        defaultParams.startTimestamp = _defaultParams.startTimestamp;
        defaultParams.cliffDuration = _defaultParams.cliffDuration;
        defaultParams.vestingDuration = _defaultParams.vestingDuration;
        defaultParams.releaseIntervalDays = _defaultParams.releaseIntervalDays;

        emit VestingParametersSet(_defaultParams.startTimestamp, _defaultParams.cliffDuration, _defaultParams.vestingDuration, _defaultParams.releaseIntervalDays);
    }

    function _isValidVestingParams(uint256 _startTimestamp, uint256 _cliffDuration, uint256 _vestingDuration, uint256 _releaseIntervalDays) internal virtual view returns (bool) {
        if (_startTimestamp == 0 || _vestingDuration == 0 || _releaseIntervalDays == 0) return false;
        if (_cliffDuration > _vestingDuration) return false;
        if (_vestingDuration < _releaseIntervalDays * SECONDS_PER_DAY) return false;
            
        return true;
    }

    /**
     * @dev Create vesting schedules for multiple beneficiaries using default parameters
     * @notice Only SCHEDULE_MANAGER_ROLE can create vesting schedules
     * @param _beneficiaries Array of beneficiary addresses
     * @param _totalAmounts Array of amounts of tokens to be vested linearly include cliff amount
     * @param _releaseAmountsAtCliff Array of amounts of tokens released at cliff
     */
    function createVestingSchedule(address[] calldata _beneficiaries, uint256[] calldata _totalAmounts, uint256[] calldata _releaseAmountsAtCliff) external virtual onlyRole(SCHEDULE_MANAGER_ROLE) {
        if (_beneficiaries.length > maxBatchForCreateVestingSchedule) revert InvalidParameterLength();
        if (_beneficiaries.length == 0) revert InvalidParameterLength();
        if (_beneficiaries.length != _totalAmounts.length) revert InvalidParameterLength();
        if (_beneficiaries.length != _releaseAmountsAtCliff.length) revert InvalidParameterLength();
        
        uint256 _totalVestedAmount = 0;
        uint256 _totalCliffVestedAmount = 0;

        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            _totalVestedAmount += _createVestingSchedule(
                _beneficiaries[i],
                _totalAmounts[i],
                _releaseAmountsAtCliff[i],
                defaultParams.startTimestamp,
                defaultParams.cliffDuration,
                defaultParams.vestingDuration,
                defaultParams.releaseIntervalDays
            );

            _totalCliffVestedAmount += _releaseAmountsAtCliff[i];
        }

        totalVestedAmount += _totalVestedAmount;
        totalCliffVestedAmount += _totalCliffVestedAmount;
    }

    /**
     * @dev Create vesting schedules for multiple beneficiaries using default parameters
     * @notice Only SCHEDULE_MANAGER_ROLE can create vesting schedules
     * @param _beneficiaries Array of beneficiary addresses
     * @param _totalAmounts Array of amounts of tokens to be vested linearly include cliff amount
     * @param _releaseAmountsAtCliff Array of amounts of tokens released at cliff
     * @param _vestingParams Array of vesting parameters
     */
    function createVestingScheduleWithCustomSchedule(address[] calldata _beneficiaries, uint256[] calldata _totalAmounts, uint256[] calldata _releaseAmountsAtCliff, DefaultVestingParams[] calldata _vestingParams) external virtual onlyRole(SCHEDULE_MANAGER_ROLE) {
        if (_beneficiaries.length > maxBatchForCreateVestingSchedule) revert InvalidParameterLength();
        if (_beneficiaries.length == 0) revert InvalidParameterLength();
        if (_beneficiaries.length != _totalAmounts.length) revert InvalidParameterLength();
        if (_beneficiaries.length != _releaseAmountsAtCliff.length) revert InvalidParameterLength();
        if (_beneficiaries.length != _vestingParams.length) revert InvalidParameterLength();
        
        uint256 _totalVestedAmount = 0;
        uint256 _totalCliffVestedAmount = 0;

        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            _totalVestedAmount += _createVestingSchedule(
                _beneficiaries[i],
                _totalAmounts[i],
                _releaseAmountsAtCliff[i],
                _vestingParams[i].startTimestamp > 0 ? _vestingParams[i].startTimestamp : defaultParams.startTimestamp,
                _vestingParams[i].cliffDuration > 0 ? _vestingParams[i].cliffDuration : defaultParams.cliffDuration,
                _vestingParams[i].vestingDuration > 0 ? _vestingParams[i].vestingDuration : defaultParams.vestingDuration,
                _vestingParams[i].releaseIntervalDays > 0 ? _vestingParams[i].releaseIntervalDays : defaultParams.releaseIntervalDays
            );

            _totalCliffVestedAmount += _releaseAmountsAtCliff[i];
        }

        totalVestedAmount += _totalVestedAmount;
        totalCliffVestedAmount += _totalCliffVestedAmount;
    }

    /**
     * @dev Internal function to create vesting schedule
     * @param _beneficiary The beneficiary address
     * @param _totalAmount The total amount of tokens to be vested linearly include cliff amount
     * @param _releaseAmountAtCliff The amount of tokens released at cliff
     * @param _startTimestamp The start timestamp of the vesting schedule
     * @param _cliffDuration The cliff duration of the vesting schedule
     * @param _vestingDuration The vesting duration of the vesting schedule
     * @param _releaseIntervalDays The release interval of the vesting schedule
     */
    function _createVestingSchedule(
        address _beneficiary, 
        uint256 _totalAmount, 
        uint256 _releaseAmountAtCliff, 
        uint256 _startTimestamp, 
        uint256 _cliffDuration, 
        uint256 _vestingDuration, 
        uint256 _releaseIntervalDays
    ) internal virtual returns (uint256 _totalVestedAmount) {
        if (!_isValidVestingParams(_startTimestamp, _cliffDuration, _vestingDuration, _releaseIntervalDays)) {
            revert InvalidVestingParams();
        }
        if (_beneficiary == address(0)) revert InvalidAddress();
        if (_totalAmount == 0) revert InvalidAmount();
        if (beneficiaryVestingSchedules[_beneficiary].isActive) revert InvalidSchedule();
        if (_releaseAmountAtCliff >= _totalAmount) revert InvalidAmount();
        
        _totalVestedAmount = _totalAmount - _releaseAmountAtCliff;

        beneficiaryVestingSchedules[_beneficiary] = VestingSchedule({
            beneficiary: _beneficiary,
            totalVestedAmount: _totalVestedAmount,
            releaseAmountAtCliff: _releaseAmountAtCliff,
            claimedAmount: 0,
            startTimestamp: _startTimestamp,
            cliffDuration: _cliffDuration,
            vestingDuration: _vestingDuration,
            releaseInterval: _releaseIntervalDays * SECONDS_PER_DAY,
            isActive: true
        });
        
        if (!isBeneficiary[_beneficiary]) {
            beneficiaries.push(_beneficiary);
            isBeneficiary[_beneficiary] = true;
        }
        
        emit VestingScheduleCreated(
            _beneficiary, 
            _totalAmount, 
            _startTimestamp, 
            _cliffDuration, 
            _vestingDuration, 
            _releaseIntervalDays * SECONDS_PER_DAY
        );
    }

    /**
     * @dev Calculate the releasable amount for a beneficiary
     * @param _beneficiary The beneficiary address
     * @return The releasable amount
     */
    function releasableAmount(address _beneficiary) public virtual view returns (uint256) {
        VestingSchedule memory schedule = beneficiaryVestingSchedules[_beneficiary];
        return _calculateReleasableAmount(schedule);
    }

    /**
     * @dev Internal function to calculate releasable amount
     * @param schedule The vesting schedule
     * @return The releasable amount
     */
    function _calculateReleasableAmount(VestingSchedule memory schedule) internal virtual view returns (uint256) {
        if (!schedule.isActive) return 0;
        if (block.timestamp < schedule.startTimestamp + schedule.cliffDuration) {
            return 0;
        }
        
        uint256 cliffClaimable = 0;
        uint256 elapsedTime = block.timestamp - schedule.startTimestamp;

        // At or after cliff, release cliff amount if not claimed
        if (elapsedTime >= schedule.cliffDuration) {
            if (schedule.releaseAmountAtCliff > 0 && schedule.claimedAmount < schedule.releaseAmountAtCliff) {
                cliffClaimable = schedule.releaseAmountAtCliff - schedule.claimedAmount;
            }
        }
        
        // Only calculate linear vesting after cliff
        uint256 timeAfterCliff = elapsedTime - schedule.cliffDuration;

        // After vesting duration, release all vested amount
        if (timeAfterCliff >= schedule.vestingDuration) {
            return (schedule.totalVestedAmount + schedule.releaseAmountAtCliff) - schedule.claimedAmount;
        }

        // Calculate total intervals based on vesting duration only. ensure to ceiling up the totalIntervals
        uint256 totalIntervals = (schedule.vestingDuration + schedule.releaseInterval - 1) / schedule.releaseInterval;
        uint256 completedIntervals = timeAfterCliff / schedule.releaseInterval;

        // Ensure we don't exceed total intervals - 1 (last interval only claimable at end)
        if (completedIntervals >= totalIntervals) {
            completedIntervals = totalIntervals - 1;
        }

        // Calculate vested amount
        uint256 vestingClaimable = 0;
        uint256 vestedAmount = (schedule.totalVestedAmount * completedIntervals) / totalIntervals;
        uint256 vestingClaimed = schedule.claimedAmount > schedule.releaseAmountAtCliff ? schedule.claimedAmount - schedule.releaseAmountAtCliff : 0;

        if (vestedAmount > vestingClaimed) {
            // Calculate the claimable amount of vested amount
            vestingClaimable = vestedAmount - vestingClaimed;
        }

        uint256 totalClaimable = cliffClaimable + vestingClaimable;
        
        // Cap claimable to total allocation minus already claimed
        uint256 totalAmount = schedule.totalVestedAmount + schedule.releaseAmountAtCliff;
        if (totalClaimable + schedule.claimedAmount > totalAmount) {
            totalClaimable = totalAmount - schedule.claimedAmount;
        }

        return totalClaimable;
    }

    /**
     * @dev Claim available vested tokens
     * @notice Claimable amount is calculated based on the vesting schedule
     */
    function claim() external virtual nonReentrant whenNotPaused onlyBeneficiary {
        _claim(_msgSender());
    }

    /**
     * @dev Release available vested tokens
     * @notice Only RELEASER_ROLE can release tokens
     * @notice Claimable amount is calculated based on the vesting schedule
     * @param beneficiary The beneficiary address
     */
    function release(address beneficiary) external virtual nonReentrant whenNotPaused onlyRole(RELEASER_ROLE) {
        _claim(beneficiary);
    }

    /**
     * @dev Release available vested tokens for multiple beneficiaries
     * @notice Only RELEASER_ROLE can release tokens
     * @notice Claimable amount is calculated based on the vesting schedule
     * @param _beneficiaries The beneficiary addresses
     */
    function releaseBatch(address[] calldata _beneficiaries) external virtual nonReentrant whenNotPaused onlyRole(RELEASER_ROLE) {
        if (_beneficiaries.length > maxBatchForRelease) revert InvalidParameterLength();
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            _claim(_beneficiaries[i]);
        }
    }

    /**
     * @dev Internal function to claim available vested tokens
     * @param beneficiary The beneficiary address
     */
    function _claim(address beneficiary) internal virtual {
        if (address(vestingToken) == address(0)) revert VestingTokenNotSet();

        uint256 claimableAmount = releasableAmount(beneficiary);
        if (claimableAmount == 0) revert InvalidAmount();

        beneficiaryVestingSchedules[beneficiary].claimedAmount += claimableAmount;

        uint256 contractBalance = vestingToken.balanceOf(address(this));
        if (contractBalance < claimableAmount) {
            revert IERC20Errors.ERC20InsufficientBalance(address(this), contractBalance, claimableAmount);
        }

        vestingToken.safeTransfer(beneficiary, claimableAmount);

        beneficiaryClaims[beneficiary].push(Claim({
            beneficiary: beneficiary,
            amount: claimableAmount,
            timestamp: block.timestamp
        }));

        emit TokensClaimed(beneficiary, claimableAmount);
    }

    /**
     * @dev Set the maximum number of beneficiaries for a single batch
     * @notice Only DEFAULT_ADMIN_ROLE can set the maximum number of beneficiaries for a single batch
     * @param _maxBatch The maximum number of beneficiaries for a single batch
     */
    function setMaxBatchForCreateVestingSchedule(uint8 _maxBatch) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxBatchForCreateVestingSchedule(_maxBatch);
    }

    /**
     * @dev Set the maximum number of beneficiaries for a single batch
     * @param _maxBatch The maximum number of beneficiaries for a single batch
     */
    function _setMaxBatchForCreateVestingSchedule(uint8 _maxBatch) internal virtual {
        if (_maxBatch == 0) revert ZeroValueParameter();
        maxBatchForCreateVestingSchedule = _maxBatch;

        emit MaxBatchForCreateVestingScheduleUpdated(_maxBatch);
    }

    /**
     * @dev Set the maximum number of beneficiaries for a single batch
     * @notice Only DEFAULT_ADMIN_ROLE can set the maximum number of beneficiaries for a single batch
     * @param _maxBatch The maximum number of beneficiaries for a single batch
     */
    function setMaxBatchForRelease(uint8 _maxBatch) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxBatchForRelease(_maxBatch);
    }

    /**
     * @dev Set the maximum number of beneficiaries for a single batch
     * @param _maxBatch The maximum number of beneficiaries for a single batch
     */
    function _setMaxBatchForRelease(uint8 _maxBatch) internal virtual {
        if (_maxBatch == 0) revert ZeroValueParameter();
        maxBatchForRelease = _maxBatch;
        
        emit MaxBatchForReleaseUpdated(_maxBatch);
    }

    /**
     * @dev Set the vesting token
     * @notice Only DEFAULT_ADMIN_ROLE can set the vesting token
     * @param _vestingToken The address of the vesting token
     */
    function setVestingToken(address _vestingToken) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_vestingToken == address(0)) revert InvalidTokenAddress();
        if (address(vestingToken) != address(0)) revert VestingTokenAlreadySet();

        address oldVestingToken = address(vestingToken);
        vestingToken = IERC20Metadata(_vestingToken);
        emit VestingTokenUpdated(oldVestingToken, _vestingToken);
    }
    
    /**
     * @dev Get vesting schedule details for a beneficiary
     * @param _beneficiary The beneficiary address
     * @return _totalVestedAmount The total amount of tokens vested linearly after cliff
     * @return _releaseAmountAtCliff The amount of tokens released at cliff
     * @return _claimedAmount The amount of tokens claimed (including cliff)
     * @return _startTimestamp The start timestamp of the vesting schedule
     * @return _cliffDuration The cliff duration of the vesting schedule
     * @return _vestingDuration The vesting duration of the vesting schedule
     * @return _releaseInterval The release interval of the vesting schedule
     * @return _isActive The active status of the vesting schedule
     */
    function getVestingSchedule(address _beneficiary) external view returns (
        uint256 _totalVestedAmount,
        uint256 _releaseAmountAtCliff,
        uint256 _claimedAmount,
        uint256 _startTimestamp,
        uint256 _cliffDuration,
        uint256 _vestingDuration,
        uint256 _releaseInterval,
        bool _isActive
    ) {
        VestingSchedule memory schedule = beneficiaryVestingSchedules[_beneficiary];
        return (
            schedule.totalVestedAmount,
            schedule.releaseAmountAtCliff,
            schedule.claimedAmount,
            schedule.startTimestamp,
            schedule.cliffDuration,
            schedule.vestingDuration,
            schedule.releaseInterval,
            schedule.isActive
        );
    }

    /**
     * @dev Get current default vesting parameters
     * @return startTimestamp The start timestamp of the vesting schedule
     * @return cliffDuration The cliff duration of the vesting schedule
     * @return vestingDuration The vesting duration of the vesting schedule
     * @return releaseIntervalDays The release interval of the vesting schedule
     */
    function getDefaultVestingParams() external virtual view returns (
        uint256 startTimestamp,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 releaseIntervalDays
    ) {
        return (
            defaultParams.startTimestamp,
            defaultParams.cliffDuration,
            defaultParams.vestingDuration,
            defaultParams.releaseIntervalDays
        );
    }

    /**
     * @dev Get all total amount of tokens vested include cliff amount
     * @return The total amount of tokens vested include cliff amount
     */
    function getAllTotalVestedAmount() external view returns (uint256) {
        return totalVestedAmount + totalCliffVestedAmount;
    }

    /**
     * @dev Emergency pause function
     * @notice Only DEFAULT_ADMIN_ROLE can pause the contract
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause function
     * @notice Only DEFAULT_ADMIN_ROLE can unpause the contract
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Withdraws foreign tokens to specified address
     * @param _token Address of the token to withdraw
     * @param _recipient Address to send the tokens to
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawForeignToken(address _token, address _recipient, uint256 _amount) external virtual onlyOwner {
        if (_token == address(vestingToken)) revert InvalidTokenAddress();
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
     * @dev Revoke a vesting schedule
     * @notice Only SCHEDULE_MANAGER_ROLE can revoke a vesting schedule
     * @param _beneficiary The beneficiary address
     */
    function revokeVestingSchedule(address _beneficiary) external onlyRole(SCHEDULE_MANAGER_ROLE) {
        if (!beneficiaryVestingSchedules[_beneficiary].isActive) revert ScheduleNotActive();
        
        beneficiaryVestingSchedules[_beneficiary].isActive = false;
        uint256 releasedAmount = beneficiaryVestingSchedules[_beneficiary].claimedAmount;
        uint256 unreleasedAmount = beneficiaryVestingSchedules[_beneficiary].totalVestedAmount + beneficiaryVestingSchedules[_beneficiary].releaseAmountAtCliff - releasedAmount;

        emit VestingScheduleRevoked(_beneficiary, releasedAmount, unreleasedAmount);
    }

    /**
     * @dev Get number of beneficiaries
     * @return The number of beneficiaries
     */
    function getBeneficiariesCount() external virtual view returns (uint256) {
        return beneficiaries.length;
    }

    /**
     * @notice Returns the beneficiaries list
     * @param offset Offset of the first item to return
     * @param limit Maximum number of items to return
     * @return result Array of beneficiaries
     * @return total Total number of beneficiaries
     */
    function getBeneficiaries(uint256 offset, uint256 limit) external view virtual returns (address[] memory result, uint256 total) {
        total = beneficiaries.length;
        
        if (offset >= total) {
            return (new address[](0), total);
        }
        
        uint256 remaining = total - offset;
        uint256 actualLimit = remaining < limit ? remaining : limit;
        
        result = new address[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit; i++) {
            result[i] = beneficiaries[offset + i];
        }
        
        return (result, total);
    }

    /**
     * @notice Returns the beneficiary vesting schedules list
     * @param offset Offset of the first item to return
     * @param limit Maximum number of items to return
     * @return result Array of beneficiary vesting schedules
     * @return total Total number of beneficiary vesting schedules
     */
    function getBeneficiaryVestingSchedules(uint256 offset, uint256 limit) external view virtual returns (VestingSchedule[] memory result, uint256 total) {
        total = beneficiaries.length;
        
        if (offset >= total) {
            return (new VestingSchedule[](0), total);
        }
        
        uint256 remaining = total - offset;
        uint256 actualLimit = remaining < limit ? remaining : limit;
        
        result = new VestingSchedule[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit; i++) {
            result[i] = beneficiaryVestingSchedules[beneficiaries[offset + i]];
        }
        
        return (result, total);
    }

    /**
     * @notice Returns the beneficiary's claim history
     * @param beneficiary Address of the beneficiary
     * @param offset Offset of the first item to return
     * @param limit Maximum number of items to return
     * @return result Array of claims
     * @return total Total number of claims
     */
    function getBeneficiaryClaimHistory(address beneficiary, uint256 offset, uint256 limit) external view virtual returns (Claim[] memory result, uint256 total) {
        total = beneficiaryClaims[beneficiary].length;
        
        if (offset >= total) {
            return (new Claim[](0), total);
        }
        
        uint256 remaining = total - offset;
        uint256 actualLimit = remaining < limit ? remaining : limit;
        
        result = new Claim[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit; i++) {
            result[i] = beneficiaryClaims[beneficiary][offset + i];
        }
        
        return (result, total);
    }
}