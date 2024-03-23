// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IERC173} from "../interfaces/IERC173.sol";
/**
 * @title OwnershipFacet
 * @dev This facet contains functions to change the owner of the contract
 *      It implements the {IERC173} interface
 */
contract OwnershipFacet is IERC173 {
    /**
     * @dev Get the address of the owner of the contract
     * @return owner_ The address of the owner of the contract
     */
    function owner() external view override returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }
    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     *
     * @param _newOwner The address of the new owner
     */
    function transferOwnership(address _newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        // Checks
        require(
            _newOwner != address(0),
            "OwnershipFacet: new owner is the zero address"
        );

        // Effects
        LibDiamond.setContractOwner(_newOwner);
    }
}
