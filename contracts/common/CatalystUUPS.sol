// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @notice Shared upgrade authorization. Production deployments must assign upgradeAuthority
/// to the approved governance/recovery route, not an externally controlled hot wallet.
abstract contract CatalystUUPS is Initializable, UUPSUpgradeable {
    address public upgradeAuthority;

    error Unauthorized();
    error ZeroAddress();

    modifier onlyUpgradeAuthority() {
        if (msg.sender != upgradeAuthority) revert Unauthorized();
        _;
    }

    function __CatalystUUPS_init(address authority) internal onlyInitializing {
        if (authority == address(0)) revert ZeroAddress();
        upgradeAuthority = authority;
    }

    function _authorizeUpgrade(address) internal view virtual override onlyUpgradeAuthority {}

    /// @dev Deliberately disable generic role-management patterns in core contracts.
    /// Implementations use explicit, bounded configuration functions instead.
}
