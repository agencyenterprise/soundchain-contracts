// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @title ZetaChain Interface Definitions
 * @notice Core interfaces for ZetaChain Universal Apps
 * @dev Based on ZetaChain Gateway architecture
 */

/// @notice Context passed to universal apps during cross-chain calls
struct MessageContext {
    uint256 chainID;     // Source chain identifier
    address sender;      // EOA or contract that initiated the call
    bytes origin;        // Original sender (for Bitcoin, etc.)
}

/// @notice Revert context for failed cross-chain calls
struct RevertContext {
    address sender;
    uint256 chainID;
    bytes revertMessage;
}

/// @notice Interface that all ZetaChain Universal Apps must implement
interface UniversalContract {
    /**
     * @notice Called when a cross-chain message arrives
     * @param context Information about the source chain and sender
     * @param zrc20 The ZRC-20 token representing the transferred asset
     * @param amount Amount of tokens transferred
     * @param message Encoded payload data
     */
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external;

    /**
     * @notice Called when a cross-chain call fails and reverts
     * @param context Revert context with error information
     */
    function onRevert(RevertContext calldata context) external;
}

/// @notice ZetaChain Gateway interface for cross-chain calls
interface IGatewayZEVM {
    /**
     * @notice Call a contract on a connected chain
     * @param receiver Target contract address on destination chain
     * @param zrc20 ZRC-20 token to use for gas/value
     * @param amount Amount to send
     * @param message Encoded call data
     * @param gasLimit Gas limit for destination execution
     * @param revertOptions Options for handling reverts
     */
    function call(
        bytes memory receiver,
        address zrc20,
        uint256 amount,
        bytes calldata message,
        uint256 gasLimit,
        RevertOptions memory revertOptions
    ) external;

    /**
     * @notice Withdraw assets to a connected chain
     * @param receiver Recipient on destination chain
     * @param amount Amount to withdraw
     * @param zrc20 ZRC-20 token to withdraw
     * @param revertOptions Options for handling reverts
     */
    function withdraw(
        bytes memory receiver,
        uint256 amount,
        address zrc20,
        RevertOptions memory revertOptions
    ) external;
}

/// @notice Options for handling cross-chain reverts
struct RevertOptions {
    address revertAddress;    // Address to receive funds on revert
    bool callOnRevert;        // Whether to call onRevert
    address abortAddress;     // Address for abort scenarios
    bytes revertMessage;      // Message to pass on revert
    uint256 onRevertGasLimit; // Gas limit for revert handler
}

/// @notice ZRC-20 interface (ZetaChain's universal token standard)
interface IZRC20 {
    function withdraw(bytes memory to, uint256 amount) external returns (bool);
    function withdrawGasFee() external view returns (address, uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function CHAIN_ID() external view returns (uint256);
}
