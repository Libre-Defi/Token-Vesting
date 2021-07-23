pragma solidity 0.7.5;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../lib/math.sol";

contract LibreVesting is Ownable, DSMath{
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  IERC20 public token;

  uint256 constant internal SECONDS_PER_MONTH = 2592000;
  uint256 constant internal SECONDS_PER_DAY = 86400;

  event GrantAdded(address recipient, uint256 startTime, uint256 amount, uint256 vestingDuration, uint256 vestingCliff);
  event GrantRemoved(address recipient, uint256 amountVested, uint256 amountNotVested);
  event GrantTokensClaimed(address recipient, uint256 amountClaimed);

  struct Grant {
    uint256 startTime;
    uint256 amount;
    uint256 vestingDuration;
    uint256 vestingCliff;
    uint256 monthsClaimed;
    uint256 daysClaimed;
    uint256 totalClaimed;
  }
  mapping (address => Grant) public tokenGrants;

  modifier nonZeroAddress(address x) {
    require(x != address(0), "Libre-token-zero-address");
    _;
  }

  modifier noGrantExistsForUser(address _user) {
    require(tokenGrants[_user].startTime == 0, "Libre-token-user-grant-exists");
    _;
  }

  constructor(address _token) public
  nonZeroAddress(_token)
  {
    token = IERC20(_token);
  }

  /// @notice Add a new token grant for user `_recipient`. Only one grant per user is allowed
  /// The amount of Libre tokens here need to be preapproved for transfer by this `Vesting` contract before this call
  /// @param _recipient Address of the token grant recipient entitled to claim the grant funds
  /// @param _startTime Grant start time as seconds since unix epoch
  /// Allows backdating grants by passing time in the past. If `0` is passed here current blocktime is used. 
  /// @param _amount Total number of tokens in grant
  /// @param _vestingDuration Number of months of the grant's duration
  /// @param _vestingCliff Number of months of the grant's vesting cliff
  function addTokenGrant(address _recipient, uint256 _startTime, uint256 _amount, uint256 _vestingDuration, uint256 _vestingCliff) public 
  onlyOwner
  noGrantExistsForUser(_recipient)
  {
    require(_vestingCliff > 0, "Libre-token-zero-vesting-cliff");
    require(_vestingDuration > _vestingCliff, "Libre-token-cliff-longer-than-duration");
    uint256 amountVestedPerMonth = _amount / _vestingDuration;
    require(amountVestedPerMonth > 0, "Libre-token-zero-amount-vested-per-month");

    Grant memory grant = Grant({
      startTime: _startTime == 0 ? block.timestamp : _startTime,
      amount: _amount,
      vestingDuration: _vestingDuration,
      vestingCliff: _vestingCliff,
      monthsClaimed: 0,
      daysClaimed: 0,
      totalClaimed: 0
    });

    tokenGrants[_recipient] = grant;
    emit GrantAdded(_recipient, grant.startTime, _amount, _vestingDuration, _vestingCliff);
  }

  /// @notice Terminate token grant transferring all vested tokens to the `_recipient`
  /// and returning all non-vested tokens to the Libre MultiSig
  /// @param _recipient Address of the token grant recipient
  function removeTokenGrant(address _recipient) public 
  onlyOwner
  {
    Grant storage tokenGrant = tokenGrants[_recipient];
    uint256 monthsVested;
    uint256 amountVested;
    (monthsVested, , amountVested) = calculateGrantClaim(_recipient);
    uint256 amountNotVested = uint256(sub(sub(tokenGrant.amount, tokenGrant.totalClaimed), amountVested));

    require(token.transfer(_recipient, amountVested), "Libre-token-recipient-transfer-failed");

    tokenGrant.startTime = 0;
    tokenGrant.amount = 0;
    tokenGrant.vestingDuration = 0;
    tokenGrant.vestingCliff = 0;
    tokenGrant.monthsClaimed = 0;
    tokenGrant.daysClaimed = 0;
    tokenGrant.totalClaimed = 0;

    emit GrantRemoved(_recipient, amountVested, amountNotVested);
  }

  /// @notice Allows a grant recipient to claim their vested tokens. Errors if no tokens have vested
  /// It is advised recipients check they are entitled to claim via `calculateGrantClaim` before calling this
  function claimVestedTokens() public {
    uint256 monthsVested;
    uint256 daysClaimed;
    uint256 amountVested;
    (monthsVested, daysClaimed, amountVested) = calculateGrantClaim(msg.sender);
    require(amountVested > 0, "Libre-token-zero-amount-vested");

    Grant storage tokenGrant = tokenGrants[msg.sender];
    tokenGrant.monthsClaimed = uint256(add(tokenGrant.monthsClaimed, monthsVested));
    tokenGrant.totalClaimed = uint256(add(tokenGrant.totalClaimed, amountVested));
    tokenGrant.daysClaimed = uint256(add(tokenGrant.daysClaimed, daysClaimed));
    
    require(token.transfer(msg.sender, amountVested), "Libre-token-sender-transfer-failed");
    emit GrantTokensClaimed(msg.sender, amountVested);
  }

  /// @notice Calculate the vested and unclaimed months and tokens available for `_recepient` to claim
  /// Due to rounding errors once grant duration is reached, returns the entire left grant amount
  /// Returns (0, 0) if cliff has not been reached
  function calculateGrantClaim(address _recipient) public view returns (uint256, uint256, uint256) {
    Grant storage tokenGrant = tokenGrants[_recipient];

    // For grants created with a future start date, that hasn't been reached, return 0, 0
    if (block.timestamp < tokenGrant.startTime) {
      return (0, 0, 0);
    }

    // Check cliff was reached
    uint256 elapsedTime = sub(block.timestamp, tokenGrant.startTime);
    uint256 elapsedMonths = elapsedTime / SECONDS_PER_MONTH;
    
    if (elapsedMonths < tokenGrant.vestingCliff) {
      return (0, 0, 0);
    }

    // If over vesting duration, all tokens vested
    if (uint256(sub(elapsedMonths, tokenGrant.vestingCliff)) >= tokenGrant.vestingDuration) {
      uint256 remainingGrant = tokenGrant.amount - tokenGrant.totalClaimed;
      return (tokenGrant.vestingDuration, uint256(mul(tokenGrant.vestingDuration, 30)), remainingGrant);
    } else {
      uint256 monthsVested = uint256(sub(uint256(sub(elapsedMonths, tokenGrant.vestingCliff)), tokenGrant.monthsClaimed));
      /*uint256 amountVestedPerMonth = tokenGrant.amount / tokenGrant.vestingDuration;
      uint256 amountVested = uint256(mul(monthsVested, amountVestedPerMonth));*/
      uint256 elapsedDays = elapsedTime / SECONDS_PER_DAY;
      uint256 daysVested = uint256(sub(uint256(sub(elapsedDays, uint256(mul(30, tokenGrant.vestingCliff)))), tokenGrant.daysClaimed));
      uint256 amountVestedPerDay = tokenGrant.amount / uint256(mul(tokenGrant.vestingDuration, 30));
      uint256 amountVested = uint256(mul(daysVested, amountVestedPerDay));
      return (monthsVested, daysVested, amountVested);
    }
  }
}
