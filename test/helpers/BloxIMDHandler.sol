// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BloxIMD} from "src/BloxIMD.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BloxIMDTestSupport} from "./BloxIMDTestSupport.sol";

/// @dev A closed population makes the sum of balances exhaustive. Actor 0 is also the
/// immediate deployer. Ghost balances and allowances start from the requested allocation
/// and change only on authorized actions; they are never copied from the token's getters.
contract BloxIMDHandler is BloxIMDTestSupport {
    BloxIMD public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public positiveTransfers;
    uint256 public positiveDelegatedTransfers;
    uint256 public rejectedCalls;

    constructor() {
        token = new BloxIMD();
        require(token.totalSupply() == SUPPLY, "incorrect initial supply");
        require(token.balanceOf(address(this)) == SUPPLY, "incorrect initial recipient");
        actors = [
            address(this),
            address(uint160(uint256(keccak256("BLOX invariant Alice")))),
            address(uint160(uint256(keccak256("BLOX invariant Bob")))),
            address(uint160(uint256(keccak256("BLOX invariant Carol"))))
        ];
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = SUPPLY / actors.length;
            if (i != 0) require(token.transfer(actors[i], SUPPLY / actors.length), "initial distribution failed");
        }
        // Seed some useful allowances so delegated calls can move value immediately.
        // Later approvals, revocations and spending are independent random actions.
        for (uint256 i; i < actors.length; ++i) {
            _approve(actors[i], actors[(i + 1) % actors.length], i == 0 ? type(uint256).max : SUPPLY / 4);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        require(token.transfer(to, amount), "valid transfer returned false");
        _recordMove(from, to, amount);
        if (amount > 0 && from != to) ++positiveTransfers;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 kind = amountSeed % 5;
        uint256 amount;
        if (kind == 1) amount = type(uint256).max;
        else if (kind == 2) amount = type(uint256).max - 1;
        else if (kind > 2) amount = bound(amountSeed, 0, SUPPLY);
        // kind == 0 revokes, even if a previous approval was unlimited.
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 amount = _amount(amountSeed, _minimum(expectedBalance[owner], allowed));
        vm.prank(spender);
        require(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        _recordMove(owner, to, amount);
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
        if (amount > 0 && owner != to) ++positiveDelegatedTransfers;
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _expectRejected(
            from,
            abi.encodeCall(token.transfer, (_actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function transferFromOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        // An unlimited approval cannot be exceeded. Revoke it first, then test that
        // the formerly authorized spender cannot continue spending from the owner.
        if (allowed == type(uint256).max) {
            _approve(owner, spender, 0);
            allowed = 0;
        }
        uint256 amount = bound(amountSeed, allowed + 1, type(uint256).max);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
    }

    function transferFromOverBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        // Ensure allowance is sufficient and finite. The later balance failure must
        // roll back the provisional allowance debit as well as all token balances.
        _approve(owner, spender, amount);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 cap = expectedBalance[owner];
        if (delegated) cap = _minimum(cap, expectedAllowance[owner][spender]);
        uint256 amount = _amount(amountSeed, cap);
        bytes memory data = delegated
            ? abi.encodeCall(token.transferFrom, (owner, address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        _expectRejected(
            delegated ? spender : owner,
            data,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _expectRejected(
            _actor(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        require(token.approve(spender, amount), "valid approval returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function _recordMove(address from, address to, uint256 amount) private {
        if (from == to) return;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _expectRejected(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        require(!success, "invalid operation succeeded");
        require(keccak256(result) == keccak256(expectedError), "unexpected failure reason");
        // No ghost state changes for rejected calls. The invariant checks the whole
        // ledger, including unrelated actors and allowances, after this action.
        ++rejectedCalls;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function _minimum(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _amount(uint256 seed, uint256 cap) private pure returns (uint256) {
        uint256 kind = seed % 5;
        if (kind == 0) return 0;
        if (kind == 1) return cap;
        if (kind == 2) return cap == 0 ? 0 : 1;
        return bound(seed, 0, cap);
    }
}
