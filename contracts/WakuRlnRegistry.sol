// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {WakuRln} from "./WakuRln.sol";
import {IPoseidonHasher} from "rln-contract/PoseidonHasher.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import "forge-std/console.sol";

error StorageAlreadyExists(address storageAddress);
error NoStorageContractAvailable();
error IncompatibleStorage();
error IncompatibleStorageIndex();

contract WakuRlnRegistry is Ownable {
    uint16 public nextStorageIndex;
    mapping(uint16 => address) public storages;

    uint16 public usingStorageIndex = 0;

    IPoseidonHasher public immutable poseidonHasher;

    event NewStorageContract(uint16 index, address storageAddress);

    constructor(address _poseidonHasher) Ownable() {
        poseidonHasher = IPoseidonHasher(_poseidonHasher);
    }

    function _insertIntoStorageMap(address storageAddress) internal {
        storages[nextStorageIndex] = storageAddress;
        emit NewStorageContract(nextStorageIndex, storageAddress);
        nextStorageIndex += 1;
    }

    function registerStorage(address storageAddress) external onlyOwner {
        if (storages[nextStorageIndex] != address(0)) revert StorageAlreadyExists(storageAddress);
        WakuRln wakuRln = WakuRln(storageAddress);
        if (wakuRln.poseidonHasher() != poseidonHasher) revert IncompatibleStorage();
        if (wakuRln.contractIndex() != nextStorageIndex) revert IncompatibleStorageIndex();
        _insertIntoStorageMap(storageAddress);
    }

    function newStorage() external onlyOwner {
        WakuRln newStorageContract = new WakuRln(address(poseidonHasher), nextStorageIndex);
        _insertIntoStorageMap(address(newStorageContract));
    }

    function register(uint256[] calldata commitments) external payable {
        if (usingStorageIndex >= nextStorageIndex) revert NoStorageContractAvailable();

        // iteratively check if the storage contract is full, and increment the usingStorageIndex if it is
        while (true) {
            try WakuRln(storages[usingStorageIndex]).register(commitments) {
                break;
            } catch (bytes memory err) {
                if (keccak256(err) != keccak256(abi.encodeWithSignature("FullTree()"))) {
                    assembly {
                        revert(add(32, err), mload(err))
                    }
                }
                usingStorageIndex += 1;
            }
        }
    }

    function forceProgress() external onlyOwner {
        if (usingStorageIndex >= nextStorageIndex) revert NoStorageContractAvailable();
        usingStorageIndex += 1;
    }
}