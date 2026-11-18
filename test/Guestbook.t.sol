// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Guestbook} from "../src/Guestbook.sol";

// Foundry 测试：每个 test 开头的函数是独立用例，setUp 每个用例前执行
contract GuestbookTest is Test {
    Guestbook guestbook;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address carol = address(0xCA401);

    function setUp() public {
        guestbook = new Guestbook();
    }

    // ========== 发布 ==========

    function test_PostMessage_StoresCorrectly() public {
        vm.prank(alice);
        uint256 id = guestbook.postMessage("Hello on-chain!");

        assertEq(id, 0);
        assertEq(guestbook.totalMessages(), 1);
        assertEq(guestbook.messageCount(alice), 1);

        Guestbook.Message memory m = guestbook.getMessage(0);
        assertEq(m.id, 0);
        assertEq(m.author, alice);
        assertEq(m.content, "Hello on-chain!");
        assertEq(m.likes, 0);
        assertGt(m.timestamp, 0);
    }

    function test_PostMessage_IdsAutoIncrement() public {
        vm.prank(alice);
        assertEq(guestbook.postMessage("first"), 0);
        vm.prank(bob);
        assertEq(guestbook.postMessage("second"), 1);
        vm.prank(alice);
        assertEq(guestbook.postMessage("third"), 2);
        assertEq(guestbook.totalMessages(), 3);
    }

    function test_PostMessage_EmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Guestbook.MessagePosted(alice, 0, "event test", block.timestamp);
        guestbook.postMessage("event test");
    }

    function test_PostMessage_RejectsEmpty() public {
        vm.prank(alice);
        vm.expectRevert(Guestbook.EmptyContent.selector);
        guestbook.postMessage("");
    }

    function test_PostMessage_RejectsTooLong() public {
        string memory longText = new string(281);
        for (uint256 i = 0; i < 281; i++) {
            bytes(longText)[i] = "a";
        }
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Guestbook.ContentTooLong.selector, 280));
        guestbook.postMessage(longText);
    }

    // ========== 编辑 ==========

    function test_UpdateMessage_ByAuthor() public {
        vm.prank(alice);
        guestbook.postMessage("original");

        vm.prank(alice);
        guestbook.updateMessage(0, "edited");

        assertEq(guestbook.getMessage(0).content, "edited");
    }

    function test_UpdateMessage_RejectsNonAuthor() public {
        vm.prank(alice);
        guestbook.postMessage("alice's");

        vm.prank(bob);
        vm.expectRevert(Guestbook.NotAuthor.selector);
        guestbook.updateMessage(0, "hacked");

        assertEq(guestbook.getMessage(0).content, "alice's");
    }

    // ========== 删除 ==========

    function test_DeleteMessage_SwapAndPopKeepsOtherIds() public {
        vm.prank(alice);
        guestbook.postMessage("msg0");
        vm.prank(bob);
        guestbook.postMessage("msg1");
        vm.prank(carol);
        guestbook.postMessage("msg2");

        // 删除中间的 ID 1
        vm.prank(bob);
        guestbook.deleteMessage(1);

        assertEq(guestbook.totalMessages(), 2);
        assertEq(guestbook.messageCount(bob), 0);
        // 关键：ID 0 和 2 不受影响，内容仍正确
        assertEq(guestbook.getMessage(0).content, "msg0");
        assertEq(guestbook.getMessage(2).content, "msg2");
        // 再读被删的 ID 应回滚
        vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageNotFound.selector, 1));
        guestbook.getMessage(1);
    }

    function test_DeleteMessage_RejectsNonAuthor() public {
        vm.prank(alice);
        guestbook.postMessage("alice's");

        vm.prank(bob);
        vm.expectRevert(Guestbook.NotAuthor.selector);
        guestbook.deleteMessage(0);

        assertEq(guestbook.totalMessages(), 1);
    }

    function test_DeletedIdNeverReused() public {
        vm.prank(alice);
        guestbook.postMessage("first");   // id 0
        vm.prank(alice);
        guestbook.deleteMessage(0);
        vm.prank(alice);
        uint256 newId = guestbook.postMessage("second");
        assertEq(newId, 1, "new message should get id 1, not reuse 0");
    }

    // ========== 点赞 ==========

    function test_LikeMessage() public {
        vm.prank(alice);
        guestbook.postMessage("like me");

        vm.prank(bob);
        guestbook.likeMessage(0);

        assertEq(guestbook.getLikes(0), 1);
        assertTrue(guestbook.hasLiked(0, bob));
        assertFalse(guestbook.hasLiked(0, alice));
    }

    function test_LikeMessage_RejectsDuplicate() public {
        vm.prank(alice);
        guestbook.postMessage("like me");

        vm.prank(bob);
        guestbook.likeMessage(0);
        vm.prank(bob);
        vm.expectRevert(Guestbook.AlreadyLiked.selector);
        guestbook.likeMessage(0);

        assertEq(guestbook.getLikes(0), 1);
    }

    function test_UnlikeMessage() public {
        vm.prank(alice);
        guestbook.postMessage("like me");

        vm.prank(bob);
        guestbook.likeMessage(0);
        vm.prank(bob);
        guestbook.unlikeMessage(0);

        assertEq(guestbook.getLikes(0), 0);
        assertFalse(guestbook.hasLiked(0, bob));
    }

    function test_UnlikeMessage_RejectsWhenNotLiked() public {
        vm.prank(alice);
        guestbook.postMessage("msg");

        vm.prank(bob);
        vm.expectRevert(Guestbook.NotLiked.selector);
        guestbook.unlikeMessage(0);
    }

    // ========== 查询 ==========

    function test_GetMessages_Pagination() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            guestbook.postMessage(string.concat("msg", vm.toString(i)));
        }

        Guestbook.Message[] memory page = guestbook.getMessages(1, 2);
        assertEq(page.length, 2);
        assertEq(page[0].id, 1);
        assertEq(page[1].id, 2);

        // 越界时自动截断
        Guestbook.Message[] memory tail = guestbook.getMessages(4, 10);
        assertEq(tail.length, 1);
        assertEq(tail[0].id, 4);

        // offset 超出总数返回空数组
        assertEq(guestbook.getMessages(10, 2).length, 0);
    }

    function test_GetMessagesByAuthor() public {
        vm.prank(alice);
        guestbook.postMessage("alice 1");
        vm.prank(bob);
        guestbook.postMessage("bob 1");
        vm.prank(alice);
        guestbook.postMessage("alice 2");

        Guestbook.Message[] memory aliceMsgs = guestbook.getMessagesByAuthor(alice);
        assertEq(aliceMsgs.length, 2);
        assertEq(aliceMsgs[0].content, "alice 1");
        assertEq(aliceMsgs[1].content, "alice 2");

        assertEq(guestbook.getMessagesByAuthor(bob).length, 1);
    }

    function test_GetMessage_RejectsMissing() public {
        vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageNotFound.selector, 99));
        guestbook.getMessage(99);
    }

    function test_GetMessages_RejectsZeroLimit() public {
        vm.expectRevert(abi.encodeWithSelector(Guestbook.InvalidPage.selector, 0, 0));
        guestbook.getMessages(0, 0);
    }
}
