// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BloxIMD} from "src/BloxIMD.sol";
import {BloxIMDHandler} from "./helpers/BloxIMDHandler.sol";
import {BloxIMDTestSupport} from "./helpers/BloxIMDTestSupport.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract BloxIMDInvariantTest is BloxIMDTestSupport {
    BloxIMDHandler private handler;
    BloxIMD private token;

    // These getter signatures are the native Foundry invariant targeting interface.
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public {
        handler = new BloxIMDHandler();
        token = handler.token();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.transferOverBalance.selector;
        selectors[4] = handler.transferFromOverAllowance.selector;
        selectors[5] = handler.transferFromOverBalance.selector;
        selectors[6] = handler.transferToZero.selector;
        selectors[7] = handler.approveZeroSpender.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    /// @dev Fixed supply and exact transfers are guarantees of this token's specification.
    function invariant_supplyEqualsSumOfAllReachableBalances() public view {
        require(token.totalSupply() == SUPPLY, "fixed supply changed");
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        require(sum == SUPPLY, "tokens created, lost, or diverted outside the actor set");
        require(token.balanceOf(address(0)) == 0, "tokens credited to zero address");
        require(token.balanceOf(address(token)) == 0, "unexpected token custody");
    }

    /// @dev Conservation alone would miss theft between actors. This checks which
    /// accounts were authorized to give or receive each amount, including self-transfers.
    function invariant_balancesMatchAuthorizedTransfers() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            require(token.balanceOf(actor) == handler.expectedBalance(actor), "balance differs from authorized flows");
        }
    }

    /// @dev Includes all owner/spender pairs, so cross-account writes and failed-call
    /// side effects cannot hide behind the active pair. Unlimited allowances stay unlimited.
    function invariant_allowancesMatchAuthorizations() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                require(
                    token.allowance(owner, spender) == handler.expectedAllowance(owner, spender),
                    "allowance differs from owner authorizations and spending"
                );
            }
            require(token.allowance(owner, address(0)) == 0, "zero spender authorized");
            require(token.allowance(address(0), owner) == 0, "zero owner authorized");
        }
    }

    /// @dev Every sequence must leave each holder able to transfer its full balance.
    /// This runs after the invariant campaign's sequence, not as a random handler action.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            vm.prank(actor);
            require(token.transfer(address(this), balance), "holder cannot transfer entire balance");
            require(token.balanceOf(actor) == 0, "holder balance not fully transferable");
        }
        require(token.balanceOf(address(this)) == SUPPLY, "final collection lost tokens");
        require(token.totalSupply() == SUPPLY, "final collection changed supply");
        require(keccak256(bytes(token.name())) == keccak256("BloxIMD"), "name changed");
        require(keccak256(bytes(token.symbol())) == keccak256("BLOX"), "symbol changed");
        require(token.decimals() == 18, "decimals changed");
    }

    /// @dev Deterministic replay demonstrates that the handler moves real value and
    /// reaches every failure action; it also pins zero, one, full-balance and max inputs.
    function test_handlerExercisesTransfersAndRejections() public {
        _checkAll();
        handler.transfer(0, 2, 2); // one base unit
        _checkAll();
        handler.transferFrom(0, 1, 3, 1); // whole remaining balance under unlimited approval
        _checkAll();
        handler.approve(3, 2, 3);
        handler.transferFrom(3, 2, 3, 2); // delegated self-transfer spends one allowance unit
        _checkAll();
        handler.approve(3, 2, 0); // revoke
        handler.transferFrom(3, 2, 1, 0); // zero spend without allowance
        _checkAll();
        handler.transferOverBalance(0, 0, type(uint256).max);
        _checkAll();
        handler.transferFromOverAllowance(3, 2, 1, 1);
        _checkAll();
        handler.transferFromOverBalance(3, 2, 1, type(uint256).max);
        _checkAll();
        handler.transferToZero(3, 2, 1, true);
        _checkAll();
        handler.transferToZero(1, 0, 0, false);
        _checkAll();
        handler.approveZeroSpender(3, type(uint256).max);
        _checkAll();
        require(handler.positiveTransfers() > 0, "handler never moved value directly");
        require(handler.positiveDelegatedTransfers() > 0, "handler never moved value with approval");
        require(handler.rejectedCalls() == 6, "failure actions were not exercised");
        afterInvariant();
    }

    function _checkAll() private view {
        invariant_supplyEqualsSumOfAllReachableBalances();
        invariant_balancesMatchAuthorizedTransfers();
        invariant_allowancesMatchAuthorizations();
    }
}
