// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Script, console} from "forge-std/Script.sol";
import {Registry} from "../../scripts/helpers/interfaces/Registry.generated.sol";
import {Governance} from "../../scripts/helpers/interfaces/Governance.generated.sol";
import {Timelock} from "../../contracts/common/misc/ITimelock.sol";
import {stdJson} from "forge-std/StdJson.sol";

interface IStakeManager {
    function getValidatorContract(uint256 validatorId) external view returns (address);
}

interface IValidatorShare {
    function _cacheDomainSeparatorV4() external returns (bytes32);
}

contract InitPermit is Script {
    using stdJson for string;

    address constant STAKE_MANAGER = 0x5e3Ef299fDDf15eAa0432E6e66473ace8c13D908;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        IStakeManager stakeManager = IStakeManager(STAKE_MANAGER);

        uint256 successCount = 0;
        uint256 failCount = 0;

        vm.startBroadcast(deployerPrivateKey);

        // Iterate from validator ID 1 to 196
        for (uint256 i = 1; i <= 196; i++) {
            try stakeManager.getValidatorContract(i) returns (address validatorShareAddress) {
                if (validatorShareAddress != address(0)) {
                    console.log("Processing validator", i, "at", validatorShareAddress);

                    try IValidatorShare(validatorShareAddress)._cacheDomainSeparatorV4() returns (
                        bytes32 domainSeparator
                    ) {
                        console.log("Successfully initialized permit for validator", i);
                        console.logBytes32(domainSeparator);
                        successCount++;
                    } catch {
                        console.log("Failed to cache domain separator for validator", i);
                        failCount++;
                    }
                } else {
                    console.log("Validator", i, "has no contract address");
                }
            } catch {
                console.log("Failed to get validator contract for validator", i);
                failCount++;
            }
        }

        console.log("=== Summary ===");
        console.log("Successfully initialized:", successCount);
        console.log("Failed:", failCount);

        vm.stopBroadcast();
    }
}
