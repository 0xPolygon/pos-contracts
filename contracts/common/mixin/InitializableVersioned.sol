pragma solidity ^0.5.2;

// Initializable with versioned reinitializers. `initializedVersion` reuses the byte of `inited`, so
// `true` reads as version 1.
contract InitializableVersioned {
    uint8 internal initializedVersion;

    modifier initializer() {
        require(initializedVersion == 0, "already inited");
        initializedVersion = 1;
        _;
    }

    modifier reinitializer(uint8 version) {
        require(initializedVersion < version, "already inited");
        initializedVersion = version;
        _;
    }

    function _disableInitializer() internal {
        initializedVersion = uint8(-1);
    }
}
