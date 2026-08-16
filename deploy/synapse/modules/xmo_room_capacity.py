"""Enforce XMO group and channel capacity on this Synapse homeserver.

The module treats only rooms carrying XMO's xmo.room.type state event as
managed rooms. Groups are capped at 50 joined users and channels at 100.
"""

from __future__ import annotations

import logging
from typing import Any, Mapping

from synapse.module_api import NOT_SPAM
from synapse.module_api.errors import Codes


logger = logging.getLogger(__name__)


class XmoRoomCapacityModule:
    """Synapse spam-checker callbacks for XMO room membership limits."""

    def __init__(self, config: Mapping[str, Any], api: Any) -> None:
        self._api = api
        self._group_member_limit = self._positive_limit(
            config.get("group_member_limit", 50), "group_member_limit"
        )
        self._channel_member_limit = self._positive_limit(
            config.get("channel_member_limit", 100), "channel_member_limit"
        )
        api.register_spam_checker_callbacks(
            user_may_join_room=self.user_may_join_room,
            user_may_invite=self.user_may_invite,
        )

    async def user_may_join_room(
        self, user_id: str, room_id: str, is_invited: bool
    ) -> Any:
        return await self._allow_membership(room_id, user_id)

    async def user_may_invite(
        self, inviter_userid: str, invitee_userid: str, room_id: str
    ) -> Any:
        return await self._allow_membership(room_id, invitee_userid)

    async def _allow_membership(self, room_id: str, user_id: str) -> Any:
        room_type, joined_users = await self._room_capacity_state(room_id)
        if room_type is None or user_id in joined_users:
            return NOT_SPAM

        limit = (
            self._channel_member_limit
            if room_type == "channel"
            else self._group_member_limit
        )
        if len(joined_users) < limit:
            return NOT_SPAM

        logger.info(
            "Rejected %s membership for full XMO %s %s (%s/%s)",
            user_id,
            room_type,
            room_id,
            len(joined_users),
            limit,
        )
        return Codes.FORBIDDEN

    async def _room_capacity_state(self, room_id: str) -> tuple[str | None, set[str]]:
        state = await self._api.get_room_state(
            room_id,
            event_filter=[("xmo.room.type", ""), ("m.room.member", None)],
        )
        room_type_event = state.get(("xmo.room.type", ""))
        room_type_content = getattr(room_type_event, "content", {}) or {}
        if room_type_content.get("is_channel") is True:
            room_type = "channel"
        elif room_type_content.get("is_group") is True:
            room_type = "group"
        else:
            return None, set()

        joined_users = {
            state_key
            for (event_type, state_key), event in state.items()
            if event_type == "m.room.member"
            and isinstance(state_key, str)
            and (getattr(event, "content", {}) or {}).get("membership") == "join"
        }
        return room_type, joined_users

    @staticmethod
    def _positive_limit(value: Any, name: str) -> int:
        try:
            limit = int(value)
        except (TypeError, ValueError) as error:
            raise ValueError(f"{name} must be a positive integer") from error
        if limit < 1:
            raise ValueError(f"{name} must be a positive integer")
        return limit
