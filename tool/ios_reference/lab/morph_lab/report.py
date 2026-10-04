import json
from pathlib import Path
import shutil


PAGE = r'''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Morph laboratory</title>
<style>
body{margin:24px;font:15px system-ui;color:#20242c;background:#f4f5f8}h1{font-size:25px}h2{font-size:19px}
section{background:white;border:1px solid #dce0e8;border-radius:12px;padding:18px;margin:18px 0}
table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}td,th{text-align:left;padding:8px;border-bottom:1px solid #eee}
.bad{color:#b21d35}.good{color:#0b7043}.muted{color:#626a78}.row{display:flex;gap:20px;flex-wrap:wrap}.panel{flex:1;min-width:280px}
button,select,input{font:inherit}input[type=range]{width:100%}canvas{max-width:100%;border:1px solid #ddd;background:#fff}
pre{overflow:auto;font-size:12px}label{margin-right:16px}#films{display:none}#viewport{overflow:auto;max-height:650px}#viewer{max-width:none;image-rendering:pixelated}
</style>
<h1 id="title"></h1><p id="status"></p><p class="muted" id="alignment"></p>
<section><h2>Capture validity</h2><div id="quality"></div><p>Marker association has presentation uncertainty. USB frame cadence and application cadence are separate measurements. Missing observations never count as a pass.</p></section>
<section><h2>Received input and semantic events</h2><div id="input"></div><label>Gesture <select id="stroke" aria-label="Gesture"></select></label><label>Coordinate <select id="touch-axis" aria-label="Coordinate"><option>x</option><option>y</option></select></label><canvas id="touch" width="900" height="300"></canvas><div id="events"></div><div id="channels" style="display:none"><label>Value channel <select id="value-channel" aria-label="Value channel"></select></label><canvas id="value-plot" width="1000" height="300"></canvas></div><h3>First observed motion</h3><div id="response"></div><p>Intervals bound the first observed change greater than 0.1 pt, 0.001 scale or 0.01 opacity. An unchanged layout container does not imply an unchanged glass surface; select an internal moving body or inspect the film.</p></section>
<section><h2>Geometry, clipping and continuity</h2><div id="geometry"></div><label>Track <select id="track" aria-label="Track"></select></label><label>Property <select id="property" aria-label="Property"></select></label><canvas id="plot" width="1000" height="300"></canvas><p>Blue: native. Orange: Flutter. Time is measured from the first received touch. Continuity limits apply only where the scenario declares them; a swipe naturally moves many points per frame.</p></section>
<section id="films"><h2>Frame inspection</h2><p id="film-quality"></p><input aria-label="Frame" id="frame" type="range" min="0" value="0"><p id="frame-info"></p><div class="row"><label>View <select id="mode" aria-label="View"><option value="split">Native / Flutter</option><option value="overlay">Overlay</option><option value="difference">Difference x4</option><option value="native">Native</option><option value="candidate">Flutter</option></select></label><label>Region <select id="region" aria-label="Region"></select></label><label>Zoom <select id="zoom" aria-label="Zoom"><option value="1">1x</option><option value="2">2x</option><option value="4">4x</option></select></label><button id="previous">Previous</button><button id="next">Next</button></div><div id="viewport"><canvas id="viewer"></canvas></div><div id="image-metrics"></div><label>Profile <select id="profile-axis" aria-label="Profile"><option>horizontal</option><option>vertical</option></select></label><canvas id="profile" width="1000" height="260"></canvas><p class="muted">Profiles average grayscale across the selected region. Image metrics use encoded SDR RGB, 0..255. They do not recover HDR highlights. Difference images include registration, content and material differences.</p></section>
<section><h2>Findings</h2><ul id="failures"></ul><details><summary>Scenario and provenance</summary><pre id="provenance"></pre></details></section>
<script>
const data=__DATA__;
const $=id=>document.getElementById(id);
const fmt=x=>x===null||x===undefined?'unobserved':typeof x==='number'?x.toFixed(3):String(x);
function cell(row,text,tag='td'){const e=document.createElement(tag);e.textContent=fmt(text);row.append(e)}
function table(target,heads,rows){const t=document.createElement('table'),h=document.createElement('tr');heads.forEach(v=>cell(h,v,'th'));t.append(h);rows.forEach(values=>{const r=document.createElement('tr');values.forEach(v=>cell(r,v));t.append(r)});$(target).replaceChildren(t)}
$('title').textContent='Morph laboratory: '+data.scenario;
$('status').textContent=data.passed?(data.fidelityGatesDeclared?'All declared checks passed':'Capture valid; no fidelity thresholds declared'):'Differences or incomplete evidence require review';$('status').className=data.passed?'good':'bad';
$('alignment').textContent=data.alignment;
table('quality',['Source','Frames','Hz','P95 gap ms','Max gap ms','P95 sampler ms','Errors'],Object.entries(data.quality).map(([k,v])=>[k,v.cadence.count,v.cadence.achievedHz,v.cadence.p95GapMs,v.cadence.maxGapMs,v.samplingCostMs.p95,v.errors.length]));
const capture=document.createElement('div');capture.id='capture-quality';$('quality').append(capture);table('capture-quality',['Source','USB Hz','USB P95 gap ms','Delegate drops','Encoder drops','Accepted','Decoded','Duplicate movie PTS','Backwards movie PTS'],Object.entries(data.quality).map(([side,q])=>{const u=q.usbSource||{},f=data.film?.[side]||{};return [side,u.cadence?.achievedHz,u.cadence?.p95GapMs,u.delegateDropCount,u.encoderDropCount,u.movieAcceptedCount,u.movieDecodedCount,f.ptsAnomalies?.duplicate,f.ptsAnomalies?.backwards]}));
table('input',['Native gestures','Flutter gestures','Path RMS pt','Duration error RMS ms','Start drift RMS ms'],[[data.input.nativeCount,data.input.candidateCount,data.input.pathErrorPt.rms,data.input.durationErrorMs.rms,data.input.startDriftMs.rms]]);
table('events',['Control','Event','Native count','Flutter count','Native final value','Flutter final value','Latency difference max ms'],data.events.groups.map(v=>[v.id,v.event,v.nativeCount,v.candidateCount,v.native.at(-1)?.value,v.candidate.at(-1)?.value,v.latencyDifferenceMs.max]));const timing=document.createElement('div');timing.id='event-timing';$('events').append(timing);table('event-timing',['Source','Control','Event','Index','From down ms','From up ms'],data.events.groups.filter(g=>g.event!=='changed').flatMap(g=>['native','candidate'].flatMap(side=>g[side].map((e,i)=>[side,g.id,g.event,i,e.fromDownMs,e.fromUpMs]))));
table('response',['Source','Gesture','Track','Earliest ms','Latest ms'],Object.entries(data.responseWindows).flatMap(([side,rows])=>rows.map(r=>[side,r.stroke,r.track,r.firstObservedResponse?.lowerMs,r.firstObservedResponse?.upperMs])));
table('geometry',['Track','Paired','Native','Flutter','Max x step pt','Max clip loss pt','Identity changes'],Object.entries(data.geometry.tracks).map(([k,v])=>[k,v.pairedCount,v.nativeCount,v.candidateCount,v.maxHorizontalStepPt,v.maxClipLossPt,v.identityChanges]));
function option(target,value,label){const e=document.createElement('option');e.value=value;e.textContent=label||value;$(target).append(e)}
function chart(canvas,series,unit="s"){const ctx=canvas.getContext('2d'),w=canvas.width,h=canvas.height;ctx.clearRect(0,0,w,h);const points=series.flatMap(s=>s.points).filter(p=>Number.isFinite(p[0])&&Number.isFinite(p[1]));if(!points.length)return;let xmin=Math.min(...points.map(p=>p[0])),xmax=Math.max(...points.map(p=>p[0])),ymin=Math.min(...points.map(p=>p[1])),ymax=Math.max(...points.map(p=>p[1]));if(xmax===xmin)xmax=xmin+1;if(ymax===ymin)ymax=ymin+1;const x=v=>55+(v-xmin)/(xmax-xmin)*(w-80),y=v=>h-35-(v-ymin)/(ymax-ymin)*(h-65);ctx.font='13px system-ui';ctx.fillStyle='#555';ctx.fillText(ymax.toFixed(3),4,20);ctx.fillText(ymin.toFixed(3),4,h-35);ctx.fillText(xmin.toFixed(3)+' '+unit,55,h-8);ctx.fillText(xmax.toFixed(3)+' '+unit,w-90,h-8);for(const s of series){ctx.strokeStyle=s.color;ctx.lineWidth=2;ctx.beginPath();let first=true;for(const p of s.points){if(!Number.isFinite(p[1])){first=true;continue}if(first){ctx.moveTo(x(p[0]),y(p[1]));first=false}else ctx.lineTo(x(p[0]),y(p[1]))}ctx.stroke()}}
const valueGroups=data.events.groups.filter(g=>[...g.native,...g.candidate].some(e=>typeof e.value==='number'));if(valueGroups.length){$('channels').style.display='block';valueGroups.forEach((g,i)=>option('value-channel',String(i),g.id+' / '+g.event));function values(){const g=valueGroups[Number($('value-channel').value)];chart($('value-plot'),['native','candidate'].map((side,i)=>({color:i?'#db7100':'#1575df',points:g[side].map(e=>[e.t,typeof e.value==='number'?e.value:NaN])})))}$('value-channel').onchange=values;values();}
Object.keys(data.geometry.tracks).forEach(k=>option('track',k));
function geometry(){const track=data.geometry.tracks[$('track').value];if(!track)return;const property=$('property').value;chart($('plot'),['native','candidate'].map((side,i)=>({color:i?'#db7100':'#1575df',points:track[side].map(r=>[r.t,r.values[property]])})))}
function properties(){const t=data.geometry.tracks[$('track').value];$('property').replaceChildren();if(t)Object.keys(t.properties).forEach(k=>option('property',k));geometry()}
$('track').onchange=properties;$('property').onchange=geometry;properties();
data.input.strokes.forEach((s,i)=>option('stroke',String(i),'Gesture '+i));
function gesture(){const s=data.input.strokes[Number($('stroke').value)];if(!s)return;chart($('touch'),['native','candidate'].map((side,i)=>({color:i?'#db7100':'#1575df',points:s[side].map(r=>[r.t,r[$('touch-axis').value]])})));}
$('stroke').onchange=gesture;$('touch-axis').onchange=gesture;gesture();
data.failures.forEach(f=>{const e=document.createElement('li');e.textContent=f;$('failures').append(e)});
$('provenance').textContent=JSON.stringify({scenario:data.specification,native:data.provenance.native,candidate:data.provenance.candidate},null,2);
if(data.film){$('films').style.display='block';const film=data.film;$('film-quality').textContent='Aligned pairs: '+film.pairs.length+'; native marker coverage '+fmt(film.native.decodedMarkerCoverage)+'; Flutter '+fmt(film.candidate.decodedMarkerCoverage)+'; matching tolerance '+fmt(film.toleranceMs)+' ms; paired gesture coverage '+film.pairedGestureCoverage.map(w=>fmt(w.coverage*100)+'%').join(', ');$('frame').max=Math.max(0,film.pairs.length-1);option('region','full','Full canvas');(data.specification.regions||[]).forEach(r=>option('region',r.id));let generation=0;
async function draw(){const p=film.pairs[Number($('frame').value)];if(!p)return;const token=++generation;const images=await Promise.all([p.native,p.candidate].map(src=>new Promise((resolve,reject)=>{const image=new Image();image.onload=()=>resolve(image);image.onerror=reject;image.src=src})));if(token!==generation)return;const c=$('viewer'),ctx=c.getContext('2d'),scale=data.specification.canvas.scale;let rect=[0,0,images[0].width,images[0].height];const r=(data.specification.regions||[]).find(r=>r.id===$('region').value);if(r)rect=r.rect.map(v=>v*scale);const zoom=Number($('zoom').value),mode=$('mode').value;c.width=rect[2]*zoom;c.height=rect[3]*zoom;c.style.width=rect[2]/scale*zoom+"px";c.style.height=rect[3]/scale*zoom+"px";ctx.imageSmoothingEnabled=false;const paint=(img,alpha=1)=>{ctx.globalAlpha=alpha;ctx.drawImage(img,...rect,0,0,c.width,c.height)};paint(images[0]);if(mode==='candidate')paint(images[1]);if(mode==='overlay')paint(images[1],.5);if(mode==='split'){ctx.save();ctx.beginPath();ctx.rect(c.width/2,0,c.width/2,c.height);ctx.clip();paint(images[1]);ctx.restore();ctx.globalAlpha=1;ctx.strokeStyle='#ed334a';ctx.beginPath();ctx.moveTo(c.width/2,0);ctx.lineTo(c.width/2,c.height);ctx.stroke()}if(mode==='difference'){const a=ctx.getImageData(0,0,c.width,c.height);paint(images[1]);const b=ctx.getImageData(0,0,c.width,c.height);for(let i=0;i<a.data.length;i+=4){for(let j=0;j<3;j++)a.data[i+j]=Math.min(255,Math.abs(a.data[i+j]-b.data[i+j])*4);a.data[i+3]=255}ctx.putImageData(a,0,0)}ctx.globalAlpha=1;$('frame-info').textContent='Pair '+$('frame').value+'; native '+fmt(p.t)+' s; Flutter time difference '+fmt(p.deltaMs)+' ms';table('image-metrics',['Region','MAE','P95','Edge RMS'],Object.entries(p.regions).map(([k,v])=>[k,v.mae,v.p95,v.edgeRms]));profile()}
function profile(){const p=film.pairs[Number($('frame').value)];if(!p)return;const metrics=p.regions[$('region').value];if(!metrics?.profiles){$('profile').getContext('2d').clearRect(0,0,1000,260);return}const samples=metrics.profiles[$('profile-axis').value];chart($('profile'),['native','candidate'].map((side,i)=>({color:i?'#db7100':'#1575df',points:samples[side].map((v,x)=>[x/data.specification.canvas.scale,v])})), 'pt');}
for(const id of ['frame','mode','region','zoom','profile-axis'])$(id).oninput=draw;$('previous').onclick=()=>{$('frame').value=Math.max(0,Number($('frame').value)-1);draw()};$('next').onclick=()=>{$('frame').value=Math.min(film.pairs.length-1,Number($('frame').value)+1);draw()};draw();}
</script></html>'''


def write_report(result, scenario, output, native_manifest=None, candidate_manifest=None):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    data = {**result, "specification": scenario, "provenance": {"native": native_manifest, "candidate": candidate_manifest}}
    if data.get("film"):
        assets = output / "frames"
        assets.mkdir()
        for index, pair in enumerate(data["film"]["pairs"]):
            for side in ("native", "candidate"):
                source = Path(pair[side])
                destination = assets / f"{index:06d}-{side}.png"
                shutil.copyfile(source, destination)
                pair[side] = str(destination.relative_to(output))
    (output / "report.json").write_text(json.dumps(data, indent=2, allow_nan=False))
    encoded = json.dumps(data, separators=(",", ":"), allow_nan=False).replace("<", "\\u003c")
    (output / "index.html").write_text(PAGE.replace("__DATA__", encoded))
    status = ("PASS" if result["fidelityGatesDeclared"] else "EVIDENCE") if result["passed"] else "REVIEW REQUIRED"
    lines = [f"# {scenario['id']}", "", status, "", result["alignment"], ""]
    for side, quality in result["quality"].items():
        c = quality["cadence"]
        lines.append(f"- {side}: {c['count']} frames, median {c['achievedHz']} Hz, max gap {c['maxGapMs']} ms")
    lines.extend(["", f"Bounds RMS: {result['geometry']['boundsErrorPt']['rms']} pt", f"Received-path RMS: {result['input']['pathErrorPt']['rms']} pt", ""])
    lines.extend(f"- {failure}" for failure in result["failures"])
    (output / "summary.md").write_text("\n".join(lines) + "\n")
    return output / "index.html"
