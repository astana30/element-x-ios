#!/usr/bin/env python3
from pathlib import Path
import re
import stat
import sys

if len(sys.argv) != 2:
    print("usage: patch_embedded_element_call_rtc.py <EmbeddedElementCall bundle path>", file=sys.stderr)
    sys.exit(2)

bundle_dir = Path(sys.argv[1]).resolve()
html = bundle_dir / "dist" / "index.html"
if not html.is_file():
    print(f"ERROR: dist/index.html not found: {html}", file=sys.stderr)
    sys.exit(1)

html_text = html.read_text(errors="ignore")
m = re.search(r'src="(?:\./)?(assets/[^"]+\.js)"', html_text)
if not m:
    print("ERROR: exact JS asset not found in dist/index.html", file=sys.stderr)
    sys.exit(1)

js_file = (html.parent / m.group(1)).resolve()
if not js_file.is_file():
    print(f"ERROR: exact JS file not found: {js_file}", file=sys.stderr)
    sys.exit(1)

assets_dir = js_file.parent
text = js_file.read_text(errors="ignore")
changed = False

def apply_once(label: str, old: str, new: str):
    global text, changed
    if new in text:
        print(f"[OK] already patched {label}: {js_file}")
        return
    if old in text:
        text = text.replace(old, new, 1)
        changed = True
        print(f"[OK] patched {label}: {js_file}")
    else:
        print(f"[SKIP] anchor not found for {label}: {js_file}")

def first_asset_name(prefix: str, suffix: str):
    matches = sorted(assets_dir.glob(f"{prefix}-*.{suffix}"))
    if not matches:
        print(f"[SKIP] missing asset for {prefix}.{suffix}: {assets_dir}")
        return None
    return matches[0].name

def swap_asset_reference(label: str, old, new):
    global text, changed
    if not old or not new:
        return
    if old not in text:
        if new in text:
            print(f"[OK] already swapped {label}: {js_file}")
        else:
            print(f"[SKIP] asset ref not found for {label}: {old}")
        return
    text = text.replace(old, new)
    changed = True
    print(f"[OK] swapped {label}: {old} -> {new}")

# 1) bridge patch
apply_once(
    "rtc_bridge",
    'if("_unstable_getRTCTransports"in t)try{const d=await t._unstable_getRTCTransports(),h=await a(d);if(h)return Oi.info("Using backend-configured (client.getRTCTransports) SFU",h),h}catch(d){',
    'try{const d=globalThis.SALEMX_getRTCTransports?await globalThis.SALEMX_getRTCTransports():"_unstable_getRTCTransports"in t?await t._unstable_getRTCTransports():null,h=d?await a(d):null;if(h)return Oi.info("Using backend-configured (client.getRTCTransports) SFU",h),h}catch(d){'
)

# 2) log fatal SFU bootstrap errors before rethrow
apply_once(
    "sfu_fatal",
    'if(m instanceof vC||m instanceof upe)throw m;',
    'if(m instanceof vC||m instanceof upe){Oi.error("SalemX SFU bootstrap fatal",m,m&&m.name,m&&m.message,m&&m.stack);throw m};'
)

# 3) upgrade quiet debug to strong error + log when no candidate worked
apply_once(
    "sfu_candidate_failure",
    'Oi.debug(`Could not use SFU service "${h.livekit_service_url}" as SFU`,m)}return null',
    'Oi.error("SalemX SFU bootstrap failed for "+h.livekit_service_url,m,m&&m.name,m&&m.message,m&&m.stack)}return Oi.error("SalemX no usable SFU transport from candidates",d),null'
)

# 4) log backend-path error details before rethrow / generic path
apply_once(
    "backend_transport_error",
    'if(d instanceof vC)throw d;Oi.error("Unexpected error fetching RTC transports from backend",d)',
    'if(d instanceof vC){Oi.error("SalemX backend transport vC",d,d&&d.name,d&&d.message,d&&d.stack);throw d}Oi.error("SalemX backend transport path failed",d,d&&d.name,d&&d.message,d&&d.stack)'
)

# 5) use a simpler generic ringtone instead of the default Element Call ringback
swap_asset_reference("ringtone_mp3", first_asset_name("ringtone", "mp3"), first_asset_name("generic", "mp3"))
swap_asset_reference("ringtone_ogg", first_asset_name("ringtone", "ogg"), first_asset_name("generic", "ogg"))

# 6) for accepted direct 1:1 widget calls, do not sit in the web waiting state
# when the remote peer has already been seen and then disappears. The stock
# lifecycle only auto-leaves on membership removal / timeout / decline, but in
# our DM hangup case the remote participant can drop out of LiveKit before the
# membership state catches up, which leaves the UI stuck in waiting-for-media /
# waiting-for-participants. We keep this narrow by:
#   - requiring a true DM predicate (dmMember$ != null),
#   - requiring that a remote participant was previously observed,
#   - waiting a short grace window so transient reconnects do not close the call.
apply_once(
    "direct_dm_remote_peer_left_autoleave",
    'Re=dt([P,Z]).pipe(Nle(([ne])=>ne!==null&&ne!=="success"),ve(([,ne])=>ne),Yv(),Hr(([ne,_e])=>_e.length<=VY&&_e.length<ne.length),ve(()=>{}),nO(KY)),we=new Ar,de=Et===null?hb:vs(Et.lazyActions,kl.HangupCall).pipe(Ju(ne=>{Et.api.transport.reply(ne.detail,{})})),ke=Il(D,Il(we,de).pipe(ve(()=>"user"))).pipe(t.share),De=t.behavior(',
    'Re=dt([P,Z]).pipe(Nle(([ne])=>ne!==null&&ne!=="success"),ve(([,ne])=>ne),Yv(),Hr(([ne,_e])=>_e.length<=VY&&_e.length<ne.length),ve(()=>{}),nO(KY)),directPeerState=t.behavior(dt([z,$]).pipe(ve(([ne,_e])=>({isDirect:ne!==null,hasRemote:_e.reduce((He,lt)=>He+lt.participants.length,0)>0})))),directPeerLeft=directPeerState.pipe(ku((ne,_e)=>({isDirect:_e.isDirect,wasRemoteSeen:_e.isDirect&&(ne.wasRemoteSeen||_e.hasRemote),shouldLeave:_e.isDirect&&ne.wasRemoteSeen&&!_e.hasRemote}),{isDirect:!1,wasRemoteSeen:!1,shouldLeave:!1}),ut(ne=>ne.shouldLeave?Ff(1e3).pipe(ve(()=>"allOthersLeft")):hb)),we=new Ar,de=Et===null?hb:vs(Et.lazyActions,kl.HangupCall).pipe(Ju(ne=>{Et.api.transport.reply(ne.detail,{})})),ke=Il(D,Il(directPeerLeft,Il(we,de).pipe(ve(()=>"user")))).pipe(t.share),De=t.behavior('
)

if changed:
    js_file.chmod(js_file.stat().st_mode | stat.S_IWUSR)
    js_file.write_text(text)
    print(f"[DONE] wrote patched JS: {js_file}")
else:
    print(f"[DONE] no file write needed: {js_file}")
