// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import '@openzeppelin/contracts/access/Ownable2Step.sol';

/**
 * @notice Adds time-based backup admin access to an {Ownable2Step} contract.
 *
 * All code in this contract is for emergencies. It exists as a safety measure
 * and is not meant for regular use. During normal operation, `claimPrivileges`
 * is never called and ownership is never transferred.
 *
 * "Staff" means the owner or an active admin. Staff can schedule trusted
 * addresses as successors. Each successor has a time at or after which it may
 * call {claimPrivileges} and become an admin. Claiming admin privileges does
 * not change the owner. Activation never happens automatically. After an
 * address is scheduled, the contract checks only its timestamp, not whether
 * the owner has lost access.
 *
 * Successor schedules are independent; there is no order or queue. The public
 * mapping can look up only a known address, not list all successors. Events can
 * be used to track them. Any staff member can replace or remove any schedule.
 * When one successor becomes an admin, all other admins and schedules remain.
 * An active admin can schedule more successors, including one that can claim
 * immediately.
 *
 * A derived contract should use {staffOnly} on every function that backup
 * admins may need. Admins cannot call `onlyOwner` functions. Only the owner can
 * remove an active admin; admins can only remove themselves.
 *
 * If the owner calls `renounceOwnership`, the owner becomes `address(0)`.
 * {WithStaff} itself cannot restore an owner; a derived contract would need to
 * add that ability explicitly. Until then, all `onlyOwner` functions are
 * unavailable. Active admins keep their access, and existing successor
 * schedules are not removed.
 *
 * This mechanism is intended for emergencies such as permanent loss of the
 * owner's key. Every successor must be fully trusted because an active admin
 * can use all `staffOnly` functions and schedule more successors. Use several
 * successors with different activation times to avoid relying on one person.
 * Give earlier times only to the most trusted addresses.
 */
abstract contract WithStaff is Ownable2Step {
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
  error AlreadyStaff();
  error AdminNotFound();
  error InvalidTimestamp();
  error SenderIsNotStaff();
  error SuccessorNotFound();

  mapping(address => bool) public admins;
  mapping(address => uint256) public successors;

  constructor() Ownable(_msgSender()) {}

  /**
   * @dev Allows only the owner or an active admin. Use it on derived-contract
   * functions that backup admins must be able to call.
   */
  modifier staffOnly {
    address sender = _msgSender();

    if (sender != owner() && !admins[sender]) {
      revert SenderIsNotStaff();
    }

    _;
  }

  /**
   * @dev Accepts ownership and clears any admin role or successor schedule for
   * the new owner. All other roles and schedules stay unchanged.
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
   * @notice Lets the owner remove an active admin.
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
   * the past or present lets `successor` claim immediately. The schedule has no
   * expiry. The current owner and active admins cannot be scheduled.
   *
   * A separate zero-address check is intentionally omitted to save gas. While
   * an owner exists, `address(0)` can be scheduled but can never claim; staff
   * can remove its schedule like any other. After ownership is renounced, the
   * existing owner check rejects `address(0)`.
   */
  function scheduleSuccessor(
    address successor,
    uint256 timestamp
  ) external staffOnly {
    if (successor == owner() || admins[successor]) {
      revert AlreadyStaff();
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
   * @notice Removes a successor schedule before it is claimed.
   */
  function removeSuccessor(address successor) external staffOnly {
    uint256 claimableAt = successors[successor];

    if (claimableAt == 0) {
      revert SuccessorNotFound();
    }

    delete successors[successor];
    emit SuccessorRemoved(successor, claimableAt, _msgSender());
  }

  /**
   * @notice Makes the caller an admin at or after the caller's scheduled time.
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
   * @notice Lets an active admin remove its own admin privileges.
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
