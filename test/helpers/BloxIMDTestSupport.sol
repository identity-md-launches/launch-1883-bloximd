// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Native Foundry interfaces keep the tests independent of an installed test library.
interface BloxVm {
    function prank(address sender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
}

abstract contract BloxIMDTestSupport {
    BloxVm internal constant vm = BloxVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    // Expected supply comes from the assignment, not the implementation's constant or getter.
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev Inclusive bounds, preserving in-range values and accepting the entire uint256 domain.
    function bound(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (uint256) {
        require(minimum <= maximum, "invalid test bounds");
        if (value >= minimum && value <= maximum) return value;
        return minimum + value % (maximum - minimum + 1);
    }
}
