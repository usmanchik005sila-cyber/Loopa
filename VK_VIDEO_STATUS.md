# VK Video integration

Checked production video-search v9: an authenticated diagnostic invocation for
provider=vk returned "Поиск VK Видео ещё не подключён". The deployed function
requires VK_VIDEO_TOKEN; no token was read, printed, or added to this repository.
The temporary anonymous diagnostic account was removed after the check.

Playback API is loaded from https://vkvideo.ru/js/api/videoplayer.js (HTTP 200
from the execution environment). The former vk.com script endpoint could not be
reached from that environment; this is not evidence of failure on every device.
The official script exposes synchronous cached getters and timeupdate/seeked
callbacks. Polling its getters must not fabricate a fresh observation every 250 ms.

Client now observes VK playback on actual provider events and destroys the old
VK subscription when changing video. Direct-link normalization is unchanged.
The client normalizes VK links to the canonical vkvideo embed address.

Remaining checks: real embeddable video in Safari/Telegram on host and guest,
play/pause/seek and autoplay/ad transitions; availability depends on the video,
provider, network and device. Playback was not validated by merely obtaining
HTTP 200 for an embed document.

To enable catalogue search, configure VK_VIDEO_TOKEN in Supabase Edge Function
secrets with a token allowed to call video.search. Verify scopes and provider
requirements before configuring. Never put the token into client JS or chat.
The presence of a token alone does not prove API access or successful search.
