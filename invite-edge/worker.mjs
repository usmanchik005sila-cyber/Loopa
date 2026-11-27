import {serveInviteLanding} from "../supabase/functions/loopa-bot/invite-web.mjs";

export default {
  fetch(request, env) {
    return serveInviteLanding(request, env.LOOPA_INVITE_SIGNING_SECRET, env.LOOPA_INVITE_PUBLIC_ORIGIN);
  }
};
