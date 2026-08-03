pragma solidity 0.5.17;

import {IPolygonMigration} from "../../common/misc/IPolygonMigration.sol";
import {IERC20} from "../../common/oz/token/ERC20/IERC20.sol";
import {StakeManagerStorageExtensionLegacy} from "./StakeManagerStorageExtensionLegacy.sol";

// Layout used by the deployed `StakeManager` implementation
// (0x3AD88467E40399dc6Ae10427f8B0842348d9076c): the pre-POL prefix in
// `StakeManagerStorageExtensionLegacy` plus the two POL slots added for the MATIC->POL migration.
//
// The extension deployed at 0xef49Ea6996073752b6840CDA34773FFA78F78166 predates those two slots and
// therefore inherits the Legacy base directly. See StakeManagerStorageExtensionLegacy.sol.
contract StakeManagerStorageExtension is StakeManagerStorageExtensionLegacy {
    IERC20 public tokenMatic;
    IPolygonMigration public migration;
}
