// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/proposals/ProposalExecutionEngine.sol";

import "../../contracts/proposals/opensea/SharedWyvernV2Maker.sol";


import "../TestUtils.sol";
import "../DummyERC721.sol";
import "./ZoraTestUtils.sol";
import "../TestUsers.sol";

contract ListOnZoraProposalIntegrationTest is
    Test,
    TestUtils,
    ZoraTestUtils
{
    IZoraAuctionHouse ZORA =
        IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    IERC20 private constant ETH_TOKEN = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    GlobalsAdmin globalsAdmin;
    Globals globals;
    Party partyImpl;
    TokenDistributor tokenDistributor;
    PartyFactory partyFactory;
    address johnAddress;
    address dannyAddress;
    address steveAddress;

    error ZoraAuctionIdNotFound();

    constructor() ZoraTestUtils(ZORA) {}

    function setUp() public onlyForked {
      globalsAdmin = new GlobalsAdmin();
      globals = globalsAdmin.globals();
      partyImpl = new Party(globals);
      globalsAdmin.setPartyImpl(address(partyImpl));
      address globalDaoWalletAddress = address(420);
      globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);

      tokenDistributor = new TokenDistributor(globals);
      globalsAdmin.setTokenDistributor(address(tokenDistributor));

      IWyvernExchangeV2 wyvern = IWyvernExchangeV2(address(0x7f268357A8c2552623316e2562D90e642bB538E5));
      SharedWyvernV2Maker wyvernMaker = new SharedWyvernV2Maker(wyvern);
      ProposalExecutionEngine pe = new ProposalExecutionEngine(globals, wyvernMaker, ZORA);
      globalsAdmin.setProposalEng(address(pe));

      partyFactory = new PartyFactory(globals);
    }

    function testSimpleZora() public onlyForked {
      PartyParticipant john = new PartyParticipant();
      PartyParticipant danny = new PartyParticipant();
      PartyParticipant steve = new PartyParticipant();
      PartyAdmin partyAdmin = new PartyAdmin(partyFactory);

      johnAddress = address(john);
      dannyAddress = address(danny);
      steveAddress = address(steve);

      // Mint dummy NFT to partyAdmin
      DummyERC721 toadz = new DummyERC721();
      toadz.mint(address(partyAdmin));

      (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = partyAdmin.createParty(
        PartyAdmin.PartyCreationMinimalOptions({
          host1: address(partyAdmin),
          host2: address(0),
          passThresholdBps: 5100,
          totalVotingPower: 150,
          preciousTokenAddress: address(toadz),
          preciousTokenId: 1
        })
      );
      // transfer NFT to party
      partyAdmin.transferNft(toadz, 1, address(party));

      partyAdmin.mintGovNft(party, johnAddress, 50);
      partyAdmin.mintGovNft(party, dannyAddress, 50);
      partyAdmin.mintGovNft(party, steveAddress, 50);

      ListOnZoraProposal.ZoraProposalData memory zpd = ListOnZoraProposal.ZoraProposalData({
        listPrice: 1.5 ether,
        duration: 120,
        token: toadz,
        tokenId: 1
      });


      bytes memory proposalData = abi.encodeWithSelector(
          bytes4(uint32(ProposalExecutionEngine.ProposalType.ListOnZora)),
          zpd
      );

      PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
        maxExecutableTime: uint40(block.timestamp + 10000 hours),
        nonce: 1,
        proposalData: proposalData
      });


      uint256 proposalId = john.makeProposal(party, proposal);

      danny.vote(party, proposalId);
      steve.vote(party, proposalId);

      vm.warp(block.timestamp + 76 hours);

      (PartyGovernance.ProposalState s, ) = party.getProposalStates(proposalId);
      assertEq(uint40(s), uint40(PartyGovernance.ProposalState.Ready));

      console.log('pre: proposal auction id', uint256(vm.load(address(ZORA), 0x0000000000000000000000000000000000000000000000000000000000000005)));

      PartyParticipant.ExecutionOptions memory eo = PartyParticipant.ExecutionOptions({
        proposalId: proposalId,
        proposal: proposal,
        preciousTokens: preciousTokens,
        preciousTokenIds: preciousTokenIds,
        progressData: ''
      });

      john.executeProposal(party, eo);

      assertEq(toadz.ownerOf(1), address(ZORA));

      // get the zora auction id created by the proposal
      // TODO: off by 1?
      uint256 proposalAuctionId = uint256(vm.load(address(ZORA), 0x0000000000000000000000000000000000000000000000000000000000000005)) - 1;
      console.log('post: proposal auction id', proposalAuctionId);

      // zora auction lifecycle tests
      {
        // bid up zora auction
        address auctionFinalizer = 0x000000000000000000000000000000000000dEaD;
        address auctionWinner = 0x000000000000000000000000000000000000D00d;
        _bidOnZoraListing(proposalAuctionId, auctionFinalizer, 1.6 ether);
        _bidOnZoraListing(proposalAuctionId, 0x0000000000000000000000000000000000001337, 4.2 ether);
        _bidOnZoraListing(proposalAuctionId, auctionWinner, 13.37 ether);

        // have zora auction finish
        // TODO: i tried +120, and +121 and the test failed with error "Reason: Auction hasn't completed"
        vm.warp(block.timestamp + 1000000000000);

        // finalize zora auction
        ZORA.endAuction(proposalAuctionId);

        // ensure NFT is held by winner
        assertEq(toadz.ownerOf(1), auctionWinner);
      }

      // ensure ETH is held by party
      assertEq(address(party).balance, 13.37 ether);

      // distribute ETH and claim distributions
      {
        vm.prank(johnAddress);
        TokenDistributor.DistributionInfo memory distributionInfo = john.distributeEth(party, ETH_TOKEN);

        uint256 johnPrevBalance = johnAddress.balance;
        vm.prank(johnAddress);
        tokenDistributor.claim(distributionInfo, 1);
        assertEq(johnAddress.balance, (4.456666666666666662 ether) + johnPrevBalance);

        uint256 dannyPrevBalance = dannyAddress.balance;
        vm.prank(dannyAddress);
        tokenDistributor.claim(distributionInfo, 2);
        assertEq(dannyAddress.balance, (4.456666666666666662 ether) + dannyPrevBalance);

        uint256 stevePrevBalance = steveAddress.balance;
        vm.prank(steveAddress);
        tokenDistributor.claim(distributionInfo, 3);
        assertEq(steveAddress.balance, (4.456666666666666662 ether) + stevePrevBalance);
      }
    }
}
