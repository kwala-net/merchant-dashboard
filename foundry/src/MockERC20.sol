// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockERC20
 * @notice A simple ERC20 mock token representing USDC for testing purposes.
 *         Has 6 decimals to match real USDC, and exposes a public mint function.
 */
contract MockERC20 {
    // -----------------------------------------------------------------------
    // Metadata
    // -----------------------------------------------------------------------

    string public name     = "Mock USDC";
    string public symbol   = "mUSDC";
    uint8  public decimals = 6;

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // -----------------------------------------------------------------------
    // ERC20 Core
    // -----------------------------------------------------------------------

    /**
     * @notice Transfer `amount` tokens from the caller to `to`.
     * @param to      Recipient address.
     * @param amount  Number of tokens (in smallest unit, 1e-6 USDC).
     * @return True on success.
     */
    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "MockERC20: transfer to zero address");
        require(balanceOf[msg.sender] >= amount, "MockERC20: insufficient balance");
        unchecked {
            balanceOf[msg.sender] -= amount;
            balanceOf[to]         += amount;
        }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Approve `spender` to spend up to `amount` on behalf of the caller.
     * @param spender Address allowed to spend.
     * @param amount  Allowance amount.
     * @return True on success.
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        require(spender != address(0), "MockERC20: approve to zero address");
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `from` to `to` using the caller's allowance.
     * @param from    Address to debit.
     * @param to      Address to credit.
     * @param amount  Number of tokens.
     * @return True on success.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(to != address(0), "MockERC20: transfer to zero address");
        require(balanceOf[from] >= amount, "MockERC20: insufficient balance");
        require(allowance[from][msg.sender] >= amount, "MockERC20: insufficient allowance");
        unchecked {
            allowance[from][msg.sender] -= amount;
            balanceOf[from]             -= amount;
            balanceOf[to]               += amount;
        }
        emit Transfer(from, to, amount);
        return true;
    }

    // -----------------------------------------------------------------------
    // Mint (test helper)
    // -----------------------------------------------------------------------

    /**
     * @notice Mint `amount` tokens to `to`. No access control — for testing only.
     * @param to     Recipient address.
     * @param amount Number of tokens to mint.
     */
    function mint(address to, uint256 amount) external {
        require(to != address(0), "MockERC20: mint to zero address");
        totalSupply     += amount;
        balanceOf[to]   += amount;
        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Burn `amount` tokens from the caller.
     * @param amount Number of tokens to burn.
     */
    function burn(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "MockERC20: insufficient balance");
        unchecked {
            balanceOf[msg.sender] -= amount;
            totalSupply           -= amount;
        }
        emit Transfer(msg.sender, address(0), amount);
    }
}
