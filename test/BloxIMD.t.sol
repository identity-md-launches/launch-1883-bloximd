// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BloxIMD} from "../src/BloxIMD.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @dev Only the Foundry cheatcodes used by this suite; no external test dependency.
interface Vm {
    function prank(address sender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
}

/// @dev Mimics the launch's immediate deploying contract without relying on tx.origin.
contract TokenFactory {
    function deploy() external returns (BloxIMD) {
        return new BloxIMD();
    }
}

contract BloxIMDTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    BloxIMD private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new BloxIMD();
    }

    function test_metadataAndInitialSupply() public view {
        require(keccak256(bytes(token.name())) == keccak256("BloxIMD"), "name");
        require(keccak256(bytes(token.symbol())) == keccak256("BLOX"), "symbol");
        require(token.decimals() == 18, "decimals");
        require(token.INITIAL_SUPPLY() == SUPPLY, "supply constant");
        require(token.totalSupply() == SUPPLY, "total supply");
        require(token.balanceOf(address(this)) == SUPPLY, "deployer balance");
        require(token.balanceOf(ALICE) == 0, "unexpected allocation");
        require(token.balanceOf(address(0)) == 0, "zero balance");
        require(token.allowance(address(this), SPENDER) == 0, "initial allowance");
    }

    function test_constructorEmitsMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new BloxIMD();
    }

    function test_factoryReceivesEntireSupply() public {
        TokenFactory factory = new TokenFactory();
        BloxIMD launched = factory.deploy();
        require(launched.balanceOf(address(factory)) == SUPPLY, "factory allocation");
        require(launched.balanceOf(address(this)) == 0, "caller allocation");
        require(launched.totalSupply() == SUPPLY, "factory supply");
    }

    function test_transferEmitsAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 42 ether);
        require(token.transfer(ALICE, 42 ether), "transfer result");
        require(token.balanceOf(ALICE) == 42 ether, "recipient balance");
        require(token.balanceOf(address(this)) == SUPPLY - 42 ether, "sender balance");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function test_zeroTransferFromEmptyAccountEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        require(token.transfer(BOB, 0), "zero transfer");
        require(token.balanceOf(BOB) == 0, "recipient balance");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function test_selfTransferPreservesBalance() public {
        require(token.transfer(address(this), SUPPLY), "self transfer");
        require(token.balanceOf(address(this)) == SUPPLY, "self balance");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function test_transferRejectsZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        require(token.balanceOf(address(this)) == SUPPLY, "balance changed");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function test_zeroTransferStillRejectsZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transferRejectsInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == 0, "balances changed");
    }

    function test_approvalEmitsAndCanBeReplacedOrRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 50 ether);
        require(token.approve(SPENDER, 50 ether), "approve result");
        require(token.allowance(address(this), SPENDER) == 50 ether, "approval");
        require(token.approve(SPENDER, 12 ether), "replace result");
        require(token.allowance(address(this), SPENDER) == 12 ether, "replacement");
        require(token.approve(SPENDER, 0), "revoke result");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        require(token.balanceOf(address(this)) == SUPPLY, "approval moved balance");
    }

    function test_approvalRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsFiniteAllowance() public {
        token.approve(SPENDER, 50 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 20 ether);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 20 ether), "transferFrom result");
        require(token.allowance(address(this), SPENDER) == 30 ether, "remaining allowance");
        require(token.balanceOf(ALICE) == 20 ether, "received amount");
        require(token.balanceOf(address(this)) == SUPPLY - 20 ether, "sender balance");
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 30 ether);
        require(token.allowance(address(this), SPENDER) == 0, "allowance not exhausted");
        require(token.balanceOf(BOB) == 30 ether, "second recipient");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function test_transferFromPreservesMaximumAllowance() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, SUPPLY), "transferFrom result");
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "maximum allowance changed");
        require(token.balanceOf(ALICE) == SUPPLY, "recipient balance");
    }

    function test_transferFromRejectsMissingAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        require(token.balanceOf(address(this)) == SUPPLY, "balance changed");
    }

    function test_transferFromRejectsInsufficientAllowance() public {
        token.approve(SPENDER, 9);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 9, 10));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 10);
        require(token.allowance(address(this), SPENDER) == 9, "allowance changed");
        require(token.balanceOf(address(this)) == SUPPLY, "balance changed");
    }

    function test_transferFromFailureRestoresAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        require(token.allowance(ALICE, SPENDER) == 10, "allowance consumed on failure");
        require(token.balanceOf(BOB) == 0, "recipient balance changed");
    }

    function test_transferFromRejectsZeroRecipientAndRestoresAllowance() public {
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10);
        require(token.allowance(address(this), SPENDER) == 10, "allowance consumed on failure");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function test_transferFromRejectsZeroSenderEvenForZeroAmount() public {
        // Spending a finite allowance validates its owner before the transfer runs.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 0), "zero transferFrom");
        require(token.allowance(ALICE, SPENDER) == 0, "allowance changed");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function test_deployerCannotMoveHolderTokensWithoutApproval() public {
        token.transfer(ALICE, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 100 ether)
        );
        token.transferFrom(ALICE, address(this), 100 ether);
        vm.prank(ALICE);
        require(token.transfer(BOB, 100 ether), "holder transfer");
        require(token.balanceOf(BOB) == 100 ether, "holder transfer amount");
    }

    function test_noMintBurnOrAdministrativeEntrypoints() public {
        token.transfer(ALICE, 100 ether);
        bytes[9] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", ALICE, 1 ether),
            abi.encodeWithSignature("burn(uint256)", 1 ether),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1 ether),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("seize(address)", ALICE),
            abi.encodeWithSignature("initialize(address)", ALICE),
            abi.encodeWithSignature("transferOwnership(address)", ALICE),
            abi.encodeWithSignature("upgradeTo(address)", ALICE)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            require(!deployerSuccess, "deployer admin call succeeded");
            vm.prank(BOB);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            require(!strangerSuccess, "stranger admin call succeeded");
        }
        require(token.totalSupply() == SUPPLY, "supply changed");
        require(token.balanceOf(ALICE) == 100 ether, "holder balance changed");
        vm.prank(ALICE);
        require(token.transfer(BOB, 100 ether), "holder frozen");
    }

    function test_launchDistributionAndClaimArriveWhole() public {
        // Local actors represent the distributor, pool custody and remainder recipient.
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;
        require(token.transfer(ALICE, swarm), "swarm transfer");
        require(token.transfer(BOB, pool), "pool transfer");
        require(token.transfer(SPENDER, SUPPLY - swarm - pool), "remainder transfer");
        require(token.balanceOf(address(this)) == 0, "deployer remainder");
        require(token.balanceOf(ALICE) == swarm, "swarm short");
        require(token.balanceOf(BOB) == pool, "pool short");
        require(token.balanceOf(SPENDER) == SUPPLY / 10, "remainder short");
        vm.prank(ALICE);
        require(token.transfer(address(this), swarm), "claim transfer");
        require(token.balanceOf(address(this)) == swarm, "claim short");
        require(token.balanceOf(ALICE) == 0, "distributor retained tokens");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function testFuzz_transferRoundTripConservesSupply(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        require(token.transfer(ALICE, amount), "outbound transfer");
        require(token.balanceOf(ALICE) == amount, "outbound amount");
        require(token.balanceOf(address(this)) == SUPPLY - amount, "deployer balance");
        vm.prank(ALICE);
        require(token.transfer(address(this), amount), "return transfer");
        require(token.balanceOf(ALICE) == 0, "remaining balance");
        require(token.balanceOf(address(this)) == SUPPLY, "round trip balance");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function testFuzz_delegatedTransfer(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approved = rawApproval % (SUPPLY + 1);
        uint256 amount = rawAmount % (approved + 1);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, amount), "delegated transfer");
        require(token.allowance(address(this), SPENDER) == approved - amount, "allowance");
        require(token.balanceOf(ALICE) == amount, "received amount");
        require(token.balanceOf(address(this)) + token.balanceOf(ALICE) == SUPPLY, "conservation");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function testFuzz_overBalanceTransferFailsAtomically(uint256 rawExcess) public {
        uint256 amount = SUPPLY + 1 + rawExcess % (type(uint256).max - SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        require(token.balanceOf(address(this)) == SUPPLY, "sender balance changed");
        require(token.balanceOf(ALICE) == 0, "recipient balance changed");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function testFuzz_transferSequenceConservesSupply(uint256 seed) public {
        address[4] memory actors = [address(this), ALICE, BOB, SPENDER];
        for (uint256 i; i < 32; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            address from = actors[seed % 4];
            address to = actors[(seed >> 8) % 4];
            uint256 amount = (seed >> 16) % (token.balanceOf(from) + 1);
            vm.prank(from);
            require(token.transfer(to, amount), "sequence transfer");
            uint256 balances;
            for (uint256 j; j < actors.length; ++j) {
                balances += token.balanceOf(actors[j]);
            }
            require(balances == SUPPLY, "sequence conservation");
            require(token.totalSupply() == SUPPLY, "sequence supply changed");
        }
    }
}
