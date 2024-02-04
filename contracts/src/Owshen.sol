// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./SparseMerkleTree.sol";
import "./MiMC.sol";
import "./CoinWithdrawVerifier.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract Owshen {
    using Strings for uint256;

    struct Proof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
    }

    struct Point {
        uint256 x;
        uint256 y;
    }

    event Sent(
        // directed or obfuscated
        // directed or obfuscated
        uint256 _commitment // h(index, g^s, amount, token)

        // hash(g^sr) + s
        // g^(hash(g^sr) + s)
        hash(index, g^(hash(g^sr) + s), _hint_amount -  h(g^sr), _hint_tokenAddress-h(g^sr)) == _commitment

    );

    event Spend(uint256 nullifier);
    event Deposit(Point indexed pub_key, Point ephemeral, uint256 nullifier);

    CoinWithdrawVerifier coin_withdraw_verifier;
    mapping(uint256 => bool) nullifiers;

    IHasher mimc;
    SparseMerkleTree tree;
    uint256 public depositIndex = 4 ** 15;

    /**
     * @dev The constructor
     */
    constructor(IHasher _hasher, uint256 _genesis_root) {
        tree = new SparseMerkleTree(_hasher, _genesis_root);
        mimc = _hasher;
        coin_withdraw_verifier = new CoinWithdrawVerifier();
    }

    function deposit( //g^s
        Point calldata _pub_key, // g^(hash(g^sr) + s)
        Point calldata ephemeral, // g^r
        address _tokenAddress,
        uint256 _amount,
        address _from,
        address _to
    ) public payable {
        uint256 uint_tokenaddress = getUintTokenAddress(_tokenAddress);
        uint256 leaf = mimc.poseidon(
            [_pub_key.x, _pub_key.y, _amount, uint_tokenaddress]
        );
        tree.set(depositIndex, leaf);
        _processDeposit(_from, _to, _tokenAddress, _amount);
        emit Sent(
            ephemeral,
            depositIndex,
            block.timestamp,
            _amount,
            uint_tokenaddress,
            leaf
        );
        depositIndex += 1;
    }

    function _processDeposit(
        address _from,
        address _to,
        address _token,
        uint256 _amount
    ) internal {
        require(
            msg.value == 0,
            "ETH value is supposed to be 0 for ERC20 instance"
        );
        IERC20(_token).transferFrom(_from, _to, _amount);
    }

    function spend(
        uint256 nullifier,
        Proof calldata proof,
        uint256 _commitment,
        uint256 _commitment2
    ) internal {
        require(!nullifiers[nullifier], "Nullifier has been spent");
        nullifiers[nullifier] = true;
        require(
            coin_withdraw_verifier.verifyProof(
                proof.a,
                proof.b,
                proof.c,
                [root(), nullifier, _commitment, _commitment2]
            ),
            "Invalid proof"
        );
    }

    function withdraw(
        uint256 nullifier,
        Point calldata _ephemeral,
        Proof calldata proof,
        address _tokenAddress,
        uint256 _amount,
        uint256 _obfuscated_remaining_amount,
        address _to,
        uint256 _commitment
    ) public {
        uint256 uint_tokenaddress = getUintTokenAddress(_tokenAddress);
        uint256 commitment2 = mimc.poseidon([0, 0, _amount, uint_tokenaddress]);
        spend(nullifier, proof, commitment2, _commitment);
        tree.set(depositIndex, _commitment);
        IERC20 payToken = IERC20(_tokenAddress);
        payToken.transfer(_to, _amount);
        emit Sent(
            _ephemeral,
            depositIndex,
            block.timestamp,
            _obfuscated_remaining_amount,
            uint_tokenaddress,
            _commitment
        );
        emit Spend(nullifier);
        depositIndex += 1;
    }

    function send(
        uint256 nullifier,
        Proof calldata proof,
        Point calldata receiver_ephemeral,
        Point calldata sender_ephemeral,
        uint256 _commitment1,
        uint256 _commitment2,
        uint256 _receiver_token_address_hint,
        uint256 _sender_token_address_hint,
        uint256 _receiver_amount_hint,
        uint256 _sender_amount_hint,
        bool isDualOutput
    ) public {
        spend(nullifier, proof, _commitment2, _commitment1);
        tree.set(depositIndex, _commitment2);
        emit Sent(
            receiver_ephemeral,
            depositIndex,
            block.timestamp,
            _receiver_amount_hint,
            _receiver_token_address_hint,
            _commitment2
        );
        depositIndex += 1;
        if (isDualOutput) {
            tree.set(depositIndex, _commitment1);
            emit Sent(
                sender_ephemeral,
                depositIndex,
                block.timestamp,
                _sender_amount_hint,
                _sender_token_address_hint,
                _commitment1
            );
            depositIndex += 1;
        }
        emit Spend(nullifier);
    }

    /**
     * @dev whether a nullifier is already spent
     */
    function isSpent(uint256 _nullifierHash) public view returns (bool) {
        return nullifiers[_nullifierHash];
    }

    /**
     * @dev whether an array of nullifiers is already spent
     */
    function isSpentArray(
        uint256[] calldata _nullifierHashes
    ) external view returns (bool[] memory spent) {
        spent = new bool[](_nullifierHashes.length);
        for (uint256 i = 0; i < _nullifierHashes.length; i++) {
            if (isSpent(_nullifierHashes[i])) {
                spent[i] = true;
            }
        }
    }

    function root() public view returns (uint256) {
        return tree.root();
    }

    function getUintTokenAddress(
        address _token_address
    ) private pure returns (uint256) {
        return uint256(uint160(_token_address));
    }
}
