// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

/* solhint-disable reason-string */

import { SoladyOwnable } from "../utils/SoladyOwnable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IPaymaster } from "account-abstraction/contracts/interfaces/IPaymaster.sol";
import { IEntryPoint } from "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "account-abstraction/contracts/core/UserOperationLib.sol";
/**
 * Helper class for creating a paymaster.
 * provides helper methods for staking.
 * Validates that the postOp is called only by the entryPoint.
 */

abstract contract BasePaymasterCustom is IPaymaster, SoladyOwnable {
    IEntryPoint public immutable entryPoint;

    uint256 internal constant _PAYMASTER_VALIDATION_GAS_OFFSET =
        UserOperationLib.PAYMASTER_VALIDATION_GAS_OFFSET;
    uint256 internal constant _PAYMASTER_POSTOP_GAS_OFFSET =
        UserOperationLib.PAYMASTER_POSTOP_GAS_OFFSET;
    uint256 internal constant _PAYMASTER_DATA_OFFSET = UserOperationLib.PAYMASTER_DATA_OFFSET;

    constructor(address owner, IEntryPoint entryPointArg) SoladyOwnable(owner) {
        _validateEntryPointInterface(entryPointArg);
        entryPoint = entryPointArg;
    }

    /**
     * Add stake for this paymaster.
     * This method can also carry eth value to add to the current stake.
     * @param unstakeDelaySec - The unstake delay for this paymaster. Can only be increased.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{ value: msg.value }(unstakeDelaySec);
    }

    /**
     * Unlock the stake, in order to withdraw it.
     * The paymaster can't serve requests once unlocked, until it calls addStake again
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /**
     * Withdraw the entire paymaster's stake.
     * stake must be unlocked first (and then wait for the unstakeDelay to be over)
     * @param withdrawAddress - The address to send withdrawn value.
     */
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }

    /// @inheritdoc IPaymaster
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    )
        external
        override
    {
        _requireFromEntryPoint();
        _postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
    }

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    )
        external
        override
        returns (bytes memory context, uint256 validationData)
    {
        _requireFromEntryPoint();
        return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    /**
     * Add a deposit for this paymaster, used for paying for transaction fees.
     */
    function deposit() external payable virtual {
        entryPoint.depositTo{ value: msg.value }(address(this));
    }

    /**
     * Withdraw value from the deposit.
     * @param withdrawAddress - Target to send to.
     * @param amount          - Amount to withdraw.
     */
    function withdrawTo(
        address payable withdrawAddress,
        uint256 amount
    )
        external
        virtual
        onlyOwner
    {
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    /**
     * Return current paymaster's deposit on the entryPoint.
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    //sanity check: make sure this EntryPoint was compiled against the same
    // IEntryPoint of this paymaster
    function _validateEntryPointInterface(IEntryPoint entryPointArg) internal virtual {
        require(
            IERC165(address(entryPointArg)).supportsInterface(type(IEntryPoint).interfaceId),
            "IEntryPoint interface mismatch"
        );
    }

    /**
     * Validate a user operation.
     * @param userOp     - The user operation.
     * @param userOpHash - The hash of the user operation.
     * @param maxCost    - The maximum cost of the user operation.
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    )
        internal
        virtual
        returns (bytes memory context, uint256 validationData);

    /**
     * Post-operation handler.
     * (verified to be called only through the entryPoint)
     * @dev If subclass returns a non-empty context from validatePaymasterUserOp,
     *      it must also implement this method.
     * @param mode          - Enum with the following options:
     *                        opSucceeded - User operation succeeded.
     *                        opReverted  - User op reverted. The paymaster still has to pay for
     * gas.
     *                        postOpReverted - never passed in a call to postOp().
     * @param context       - The context value returned by validatePaymasterUserOp
     * @param actualGasCost - Actual gas used so far (without this postOp call).
     * @param actualUserOpFeePerGas - the gas price this UserOp pays. This value is based on the
     * UserOp's maxFeePerGas
     *                        and maxPriorityFee (and basefee)
     *                        It is not the same as tx.gasprice, which is what the bundler pays.
     */
    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    )
        internal
        virtual
    {
        (mode, context, actualGasCost, actualUserOpFeePerGas); // unused params
        // subclass must override this method if validatePaymasterUserOp returns a context
        revert("must override");
    }

    /**
     * Validate the call is made from a valid entrypoint
     */
    function _requireFromEntryPoint() internal virtual {
        require(msg.sender == address(entryPoint), "Sender not EntryPoint");
    }

    /**
     * Check if address is a contract
     */
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly ("memory-safe") {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}
