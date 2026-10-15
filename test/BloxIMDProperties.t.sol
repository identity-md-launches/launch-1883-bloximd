// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BloxIMD} from "src/BloxIMD.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BloxIMDTestSupport} from "./helpers/BloxIMDTestSupport.sol";

/// @dev A token recipient need not implement a receiver hook or accept native currency.
contract BloxRejectingRecipient {
    fallback() external {
        revert("unexpected recipient callback");
    }
}

/// forge-config: default.fuzz.runs = 1000
contract BloxIMDPropertiesTest is BloxIMDTestSupport {
    BloxIMD private token;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new BloxIMD();
    }

    function test_oneBaseUnitCanMoveWithoutRounding() public {
        require(token.transfer(ALICE, 1), "one-unit transfer failed");
        require(token.balanceOf(ALICE) == 1, "one-unit transfer rounded");
        require(token.balanceOf(address(this)) == SUPPLY - 1, "wrong debit");
        vm.prank(ALICE);
        require(token.transfer(BOB, 1), "one-unit onward transfer failed");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == 1, "wrong onward balances");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function test_fullSupplyTransferCannotBeReplayedAndCanReturn() public {
        require(token.transfer(ALICE, SUPPLY), "full transfer failed");
        require(token.balanceOf(address(this)) == 0 && token.balanceOf(ALICE) == SUPPLY, "full transfer balances");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        token.transfer(BOB, 1);
        vm.prank(ALICE);
        require(token.transfer(address(this), SUPPLY), "return failed");
        require(token.balanceOf(address(this)) == SUPPLY, "round trip lost supply");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == 0, "unexpected remainder");
    }

    function test_selfTransferStillRequiresEnoughBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        require(token.balanceOf(address(this)) == SUPPLY, "failed self-transfer changed balance");
    }

    function test_maximumTransferFailsWithoutArithmeticPanic() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        require(
            token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "failed transfer mutated balances"
        );
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        require(token.approve(SPENDER, type(uint256).max - 1), "approval failed");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 1), "spending failed");
        require(
            token.allowance(address(this), SPENDER) == type(uint256).max - 2, "finite allowance treated as infinite"
        );
        require(token.balanceOf(ALICE) == 1 && token.balanceOf(address(this)) == SUPPLY - 1, "wrong balances");
    }

    function test_exhaustedAllowanceCannotBeReplayed() public {
        token.approve(SPENDER, 1);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 1), "initial spending failed");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        require(token.allowance(address(this), SPENDER) == 0, "exhausted allowance changed");
        require(token.balanceOf(ALICE) == 1 && token.balanceOf(BOB) == 0, "replay changed balances");
        require(token.balanceOf(address(this)) == SUPPLY - 1, "replay debited owner");
    }

    function test_unlimitedAllowanceCanBeRevokedAndReplaced() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 1), "unlimited spending failed");
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "unlimited allowance decreased");
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 0);
        require(token.approve(SPENDER, 0), "revocation failed");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        require(token.balanceOf(BOB) == 0, "revoked spender moved tokens");
        require(token.approve(SPENDER, 2), "replacement failed");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), BOB, 2), "replacement could not be spent");
        require(
            token.allowance(address(this), SPENDER) == 0 && token.balanceOf(BOB) == 2, "wrong replacement accounting"
        );
        require(token.balanceOf(address(this)) == SUPPLY - 3, "wrong owner balance");
    }

    function test_delegatedSelfTransferConsumesAllowanceWithoutMovingBalance() public {
        token.approve(SPENDER, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), address(this), SUPPLY), "self-transfer failed");
        require(token.balanceOf(address(this)) == SUPPLY, "self-transfer changed balance");
        require(token.allowance(address(this), SPENDER) == 0, "self-transfer did not spend allowance");
        require(token.totalSupply() == SUPPLY, "self-transfer changed supply");
    }

    function test_ownerUsingTransferFromNeedsItsOwnAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        token.approve(address(this), 1);
        require(token.transferFrom(address(this), ALICE, 1), "self-approved spending failed");
        require(token.allowance(address(this), address(this)) == 0, "self-allowance not spent");
        require(
            token.balanceOf(ALICE) == 1 && token.balanceOf(address(this)) == SUPPLY - 1, "wrong self-approved balances"
        );
    }

    function test_unlimitedAllowanceDoesNotBypassBalanceChecks() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "failed call changed unlimited allowance");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "failed call changed balances");
        require(token.totalSupply() == SUPPLY, "failed call changed supply");
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        require(token.allowance(address(this), address(0)) == 0, "zero-spender allowance changed");
    }

    function test_zeroDelegatedTransferToZeroStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        require(
            token.balanceOf(address(this)) == SUPPLY && token.balanceOf(address(0)) == 0,
            "failed zero transfer changed balances"
        );
        require(token.allowance(address(this), SPENDER) == 0, "failed zero transfer changed allowance");
    }

    function test_contractRecipientDoesNotNeedReceiverHook() public {
        BloxRejectingRecipient receiver = new BloxRejectingRecipient();
        require(token.transfer(address(receiver), 1), "contract transfer failed");
        token.approve(SPENDER, 2);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), address(receiver), 2), "delegated contract transfer failed");
        require(
            token.balanceOf(address(receiver)) == 3 && token.balanceOf(address(this)) == SUPPLY - 3,
            "wrong contract balances"
        );
        require(token.allowance(address(this), SPENDER) == 0, "contract transfer did not spend allowance");
    }

    function testFuzz_approvalReplacementIsIdempotentAndIsolated(uint256 first, uint256 replacement) public {
        token.approve(BOB, 17);
        vm.prank(ALICE);
        token.approve(SPENDER, 19);
        require(token.approve(SPENDER, first), "first approval failed");
        require(token.approve(SPENDER, replacement), "replacement failed");
        require(token.allowance(address(this), SPENDER) == replacement, "approval accumulated instead of replacing");
        require(token.approve(SPENDER, replacement), "repeated approval failed");
        require(token.allowance(address(this), SPENDER) == replacement, "repeated approval changed allowance");
        require(token.allowance(address(this), BOB) == 17, "another spender's allowance changed");
        require(token.allowance(ALICE, SPENDER) == 19, "another owner's allowance changed");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "approval moved tokens");
        require(token.totalSupply() == SUPPLY, "approval changed supply");
    }

    function testFuzz_splitSpendingExhaustsExactlyTheApproval(uint256 rawApproval, uint256 rawFirstSpend) public {
        uint256 approved = bound(rawApproval, 1, SUPPLY);
        uint256 first = bound(rawFirstSpend, 0, approved);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, first), "first spend failed");
        require(token.allowance(address(this), SPENDER) == approved - first, "wrong intermediate allowance");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), BOB, approved - first), "second spend failed");
        require(token.allowance(address(this), SPENDER) == 0, "approval not exhausted");
        require(
            token.balanceOf(ALICE) == first && token.balanceOf(BOB) == approved - first, "split recipients incorrect"
        );
        require(token.balanceOf(address(this)) == SUPPLY - approved, "split debit incorrect");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        require(token.balanceOf(ALICE) == first, "replay changed recipient");
        require(token.balanceOf(address(this)) == SUPPLY - approved, "replay changed owner");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function testFuzz_insufficientAllowanceFailsWithSufficientBalance(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approved = bound(rawApproval, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, approved + 1, SUPPLY);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        require(token.allowance(address(this), SPENDER) == approved, "failed call consumed allowance");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(ALICE) == 0, "failed call moved tokens");
        require(token.totalSupply() == SUPPLY, "failed call changed supply");
    }

    function testFuzz_insufficientBalanceRestoresFiniteAllowance(uint256 rawBalance, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        // Keep the approval finite, including amounts far above the token's supply.
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max - 1);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        require(token.allowance(ALICE, SPENDER) == amount, "failed call consumed finite allowance");
        require(token.balanceOf(ALICE) == balance && token.balanceOf(BOB) == 0, "failed call changed holder balances");
        require(token.balanceOf(address(this)) == SUPPLY - balance, "failed call changed deployer balance");
        require(token.totalSupply() == SUPPLY, "failed call changed supply");
    }

    function testFuzz_spenderCannotUseAnotherSpendersApproval(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        token.approve(SPENDER, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, amount));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, amount);
        require(token.allowance(address(this), SPENDER) == amount, "another spender's approval consumed");
        require(token.balanceOf(address(this)) == SUPPLY && token.balanceOf(BOB) == 0, "unauthorized spending");
    }

    function testFuzz_approvalCannotBeUsedAgainstAnotherOwner(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        token.transfer(ALICE, amount);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        require(token.balanceOf(ALICE) == amount && token.balanceOf(BOB) == 0, "another owner's tokens moved");
        require(token.allowance(ALICE, SPENDER) == 0, "unauthorized approval created");
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "unrelated approval changed");
    }

    function testFuzz_transferToAnyNonzeroRecipient(address rawRecipient, uint256 rawAmount) public {
        address recipient = address(uint160(bound(uint160(rawRecipient), 1, type(uint160).max)));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), recipient, amount);
        require(token.transfer(recipient, amount), "transfer failed");
        if (recipient == address(this)) {
            require(token.balanceOf(address(this)) == SUPPLY, "self-transfer changed balance");
        } else {
            require(token.balanceOf(recipient) == amount, "recipient did not receive exact amount");
            require(token.balanceOf(address(this)) == SUPPLY - amount, "sender lost wrong amount");
        }
        require(token.totalSupply() == SUPPLY, "transfer changed supply");
    }

    function testFuzz_delegatedSelfTransferPreservesBalanceAndSpendsFiniteAllowance(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        token.approve(SPENDER, SUPPLY);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), address(this), amount), "delegated self-transfer failed");
        require(token.balanceOf(address(this)) == SUPPLY, "self-transfer changed balance");
        require(token.allowance(address(this), SPENDER) == SUPPLY - amount, "incorrect allowance consumption");
        require(token.totalSupply() == SUPPLY, "self-transfer changed supply");
    }
}
