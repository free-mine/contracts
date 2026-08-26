// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import '@openzeppelin/contracts/access/Ownable2Step.sol';

/**
 * @notice Adds a mine crew with scheduled backup admins to an {Ownable2Step}
 * contract.
 *
 * The crew consists of the owner and all active admins. Any crew member can
 * schedule a trusted address as a successor. Each successor may call
 * {claimPrivileges} at or after its scheduled time and become an admin.
 * Claiming privileges does not change the owner. Activation never happens
 * automatically. After an address is scheduled, the contract checks only its
 * timestamp, not whether the owner has lost access.
 *
 * Successor schedules are independent; there is no order or queue. The public
 * `successors` getter can check a known address but cannot list all successors.
 * Use events to discover and track schedules. Any crew member can replace or
 * remove any schedule. When one successor becomes an admin, all other admins
 * and schedules remain. An active admin can schedule more successors,
 * including one that can claim immediately.
 *
 * A derived contract should use {crew} on every function that backup admins
 * may need. Admins cannot call `onlyOwner` functions. Only the owner can remove
 * another active admin; admins can remove only themselves.
 *
 * If the owner calls `renounceOwnership`, the owner becomes `address(0)`.
 * {MineCrew} itself cannot restore an owner; a derived contract would need to
 * add that ability explicitly. Until then, all `onlyOwner` functions are
 * unavailable. Active admins keep their access, and existing successor
 * schedules are not removed.
 *
 * This mechanism is intended for emergencies such as permanent loss of the
 * owner's key. Every successor must be fully trusted because an active admin
 * can call every function protected by {crew} and schedule more successors.
 * Use several successors with different activation times to avoid relying on
 * one person. Give earlier times only to the most trusted addresses.
 */
abstract contract MineCrew is Ownable2Step {
  event SuccessorScheduled(
    address indexed successor,
    uint256 previousClaimableAt,
    uint256 claimableAt,
    address indexed scheduledBy
  );

  event SuccessorRemoved(
    address indexed successor,
    uint256 claimableAt,
    address indexed removedBy
  );

  event AdminActivated(address indexed admin, uint256 claimableAt);
  event AdminRemoved(address indexed admin);

  error NotYet();
  error AlreadyInCrew();
  error AdminNotFound();
  error InvalidTimestamp();
  error SenderIsNotInCrew();
  error SuccessorNotFound();

  mapping(address => bool) public admins;
  mapping(address => uint256) public successors;

  constructor() Ownable(_msgSender()) {}

  /**
   * @dev Allows calls only from the owner or an active admin. Use it on
   * functions in derived contracts that backup admins must be able to call.
   */
  modifier crew {
    address sender = _msgSender();

    if (sender != owner() && !admins[sender]) {
      revert SenderIsNotInCrew();
    }

    _;
  }

  /**
   * @dev Accepts ownership and removes the new owner from the admin and
   * successor mappings. All other admins and schedules stay unchanged.
   * {Ownable2Step} still requires the caller to be the pending owner;
   * otherwise the whole transaction reverts.
   */
  function acceptOwnership() public override {
    address sender = _msgSender();

    if (admins[sender]) {
      admins[sender] = false;

      emit AdminRemoved(sender);
    }

    uint256 claimableAt = successors[sender];

    if (claimableAt != 0) {
      delete successors[sender];
      emit SuccessorRemoved(sender, claimableAt, sender);
    }

    super.acceptOwnership();
  }

  /**
   * @notice Lets the owner remove an active admin from the crew.
   *
   * @dev This does not remove any successor schedules,
   * including schedules created by that admin.
   */
  function removeAdmin(address admin) external onlyOwner {
    if (!admins[admin]) {
      revert AdminNotFound();
    }

    admins[admin] = false;

    emit AdminRemoved(admin);
  }

  /**
   * @notice Sets the time from which `successor` may claim admin privileges.
   * Calling this again for the same address replaces its previous time.
   *
   * @dev `timestamp` must be nonzero because zero means no schedule. A time in
   * the past or present lets `successor` claim immediately. The schedule never
   * expires. The owner and active admins cannot be scheduled because they are
   * already in the crew.
   *
   * A separate zero-address check is intentionally omitted to save gas. While
   * an owner exists, `address(0)` can be scheduled but can never claim; any
   * crew member can remove its schedule. After ownership is renounced, the
   * owner check rejects `address(0)` because it is then the owner's address.
   */
  function scheduleSuccessor(
    address successor,
    uint256 timestamp
  ) external crew {
    if (successor == owner() || admins[successor]) {
      revert AlreadyInCrew();
    }

    if (timestamp == 0) {
      revert InvalidTimestamp();
    }

    uint256 previousTimestamp = successors[successor];

    successors[successor] = timestamp;

    emit SuccessorScheduled(
      successor,
      previousTimestamp,
      timestamp,
      _msgSender()
    );
  }

  /**
   * @notice Removes a successor schedule before the successor claims admin
   * privileges.
   */
  function removeSuccessor(address successor) external crew {
    uint256 claimableAt = successors[successor];

    if (claimableAt == 0) {
      revert SuccessorNotFound();
    }

    delete successors[successor];
    emit SuccessorRemoved(successor, claimableAt, _msgSender());
  }

  /**
   * @notice Adds the caller to the crew as an admin at or after the time
   * scheduled for that caller.
   *
   * @dev A successful claim removes only the caller's successor schedule.
   * Other admins and schedules do not change.
   */
  function claimPrivileges() external {
    address sender = _msgSender();
    uint256 claimableAt = successors[sender];

    if (claimableAt == 0) {
      revert SuccessorNotFound();
    }

    if (block.timestamp < claimableAt) {
      revert NotYet();
    }

    admins[sender] = true;

    delete successors[sender];
    emit AdminActivated(sender, claimableAt);
  }

  /**
   * @notice Lets an active admin leave the crew.
   *
   * @dev This does not transfer admin access or schedule a replacement.
   */
  function renouncePrivileges() external {
    address sender = _msgSender();

    if (!admins[sender]) {
      revert AdminNotFound();
    }

    admins[sender] = false;

    emit AdminRemoved(sender);
  }
}
