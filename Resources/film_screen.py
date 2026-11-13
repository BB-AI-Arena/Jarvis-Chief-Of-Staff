"""Bounded planar screen replacement; preserves the generated actor performance."""
import base64
import hashlib
import io
import json
import math
from pathlib import Path
import shlex
import subprocess


def validate_quad(points):
    if not isinstance(points,list) or len(points)!=4 or any(not isinstance(p,list) or len(p)!=2 or any(type(x) not in [int,float] or not math.isfinite(x) or not 0<=x<=1 for x in p) for p in points):
        raise ValueError('Invalid phone display quadrilateral')
    crosses=[]
    for i in range(4):
        a,b,c=points[i],points[(i+1)%4],points[(i+2)%4]
        crosses.append((b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]))
    area=abs(sum(points[i][0]*points[(i+1)%4][1]-points[(i+1)%4][0]*points[i][1] for i in range(4)))/2
    if min(crosses)<=0 or not .003<area<.8:raise ValueError('Phone display must be a usable clockwise convex plane')
    return points


def tracking_script():
    return r'''
import cv2,numpy as np,json,subprocess,math
from pathlib import Path
source=cfg['source'];target=cfg['target'];cap=cv2.VideoCapture(source)
ok,first=cap.read()
if not ok:raise ValueError('Cannot decode phone shot')
h,w=first.shape[:2];fps=cap.get(cv2.CAP_PROP_FPS)
if not 1<fps<121:raise ValueError('Invalid source frame rate')
q=np.array(cfg['quad'],np.float32)*[w,h];original_q=q.copy();cumulative=np.eye(3)
plate=cv2.imread(cfg['plate'])
if plate is None or plate.shape[:2]!=(h,w):raise ValueError('Screen plate geometry mismatch')
# Refine the approximate vision coordinates against the actual straight case edges.
# Using the full rigid phone plane also removes unstable pixels outside an image card.
gray_plate=cv2.cvtColor(plate,cv2.COLOR_BGR2GRAY);edges=cv2.Canny(gray_plate,30,90)
roi=np.zeros((h,w),np.uint8);lo=np.maximum(0,np.floor(q.min(axis=0)-[50,65])).astype(int);hi=np.minimum([w,h],np.ceil(q.max(axis=0)+[50,65])).astype(int)
roi[lo[1]:hi[1],lo[0]:hi[0]]=255
lines=cv2.HoughLinesP(cv2.bitwise_and(edges,roi),1,np.pi/360,15,minLineLength=25,maxLineGap=14)
if lines is None:raise ValueError('No reliable physical phone outline')
center=q.mean(axis=0);chosen=[];span=max(np.linalg.norm(q[1]-q[0]),np.linalg.norm(q[3]-q[0]))
short=min(np.linalg.norm(q[(i+1)%4]-q[i]) for i in range(4))
for i in range(4):
 a=q[i];b=q[(i+1)%4];v=b-a;length=np.linalg.norm(v);axis=v/length;outward=np.array([axis[1],-axis[0]]);mid=(a+b)/2;candidates=[]
 for segment in lines[:,0]:
  p=segment[:2].astype(float);end=segment[2:].astype(float);d=end-p;n=np.linalg.norm(d);m=(p+end)/2
  tolerance=7 if length>short*1.4 else 19
  if abs(np.dot(d/n,axis))<math.cos(math.radians(tolerance)):continue
  if abs(np.dot(m-mid,outward))>span*.14 or abs(np.dot(m-mid,axis))>length*.7:continue
  line=np.cross([p[0],p[1],1],[end[0],end[1],1]);line=line/np.linalg.norm(line[:2])
  samples=p[None]+np.linspace(.1,.9,40)[:,None]*d[None]
  inside=np.clip(np.rint(samples-outward*3),[0,0],[w-1,h-1]).astype(int)
  outside=np.clip(np.rint(samples+outward*3),[0,0],[w-1,h-1]).astype(int)
  dark=gray_plate[inside[:,1],inside[:,0]].astype(float);light=gray_plate[outside[:,1],outside[:,0]].astype(float)
  # Prefer an actual dark case boundary over a parallel finger or background line.
  score=float(np.mean(dark<48))*100+max(0,float(np.mean(light-dark)))*.7-abs(np.dot(m-mid,outward))*.4+n*.01
  candidates.append((score,line))
 if not candidates:raise ValueError('Physical phone edge could not be refined')
 chosen.append(max(candidates,key=lambda x:x[0])[1])
corners=[]
for i in range(4):
 point=np.cross(chosen[(i-1)%4],chosen[i])
 if abs(point[2])<1e-6:raise ValueError('Degenerate phone outline')
 corners.append(point[:2]/point[2])
refined=np.array(corners,np.float32)
if not cv2.isContourConvex(refined) or not .5<abs(cv2.contourArea(refined))/abs(cv2.contourArea(q.astype(np.float32)))<2.5 or np.max(np.linalg.norm(refined-q,axis=1))>span*.19:raise ValueError('Phone outline refinement is inconsistent')
q=refined;original_q=q.copy()
sw=max(16,round(max(np.linalg.norm(q[1]-q[0]),np.linalg.norm(q[2]-q[3]))))
sh=max(24,round(max(np.linalg.norm(q[3]-q[0]),np.linalg.norm(q[2]-q[1]))))
rect=np.array([[0,0],[sw-1,0],[sw-1,sh-1],[0,sh-1]],np.float32)
screen=cv2.warpPerspective(plate,cv2.getPerspectiveTransform(q.astype(np.float32),rect),(sw,sh))
mask_rect=np.ones((sh,sw),np.float32);cv2.rectangle(mask_rect,(0,0),(sw-1,sh-1),0,2)
mask_rect=cv2.GaussianBlur(mask_rect,(3,3),.6)
def region(quad):
 m=np.zeros((h,w),np.uint8);cv2.fillConvexPoly(m,quad.astype(np.int32),255)
 outer=cv2.dilate(m,np.ones((9,9),np.uint8));inner=cv2.erode(m,np.ones((15,15),np.uint8))
 return cv2.subtract(outer,inner)
def features(gray,quad):
 return cv2.goodFeaturesToTrack(gray,180,.004,3,mask=region(quad),blockSize=3)
prev=cv2.cvtColor(first,cv2.COLOR_BGR2GRAY);points=features(prev,q)
if points is None or len(points)<8:raise ValueError('Not enough phone-border features for safe tracking')
Path(target).parent.mkdir(parents=True,exist_ok=True)
args=['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','bgr24','-s',f'{w}x{h}','-r',str(fps),'-i','pipe:0','-i',source,
 '-map','0:v:0','-map','1:a?','-c:v','h264_nvenc','-preset','p6','-cq','18','-pix_fmt','yuv420p','-c:a','copy','-movflags','+faststart',target]
encoder=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
frame=first;index=0;tracked=0;holds=0;max_holds=0
try:
 while True:
  gray=cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY)
  if index:
   following,status,_=cv2.calcOpticalFlowPyrLK(prev,gray,points,None,winSize=(25,25),maxLevel=3)
   if following is None:raise ValueError('Phone tracking lost')
   back,back_status,_=cv2.calcOpticalFlowPyrLK(gray,prev,following,None,winSize=(25,25),maxLevel=3)
   valid=(status[:,0]>0)&(back_status[:,0]>0)&(np.linalg.norm(points[:,0]-back[:,0],axis=1)<1.5)
   old=points[valid];new=following[valid]
   H,inliers=cv2.findHomography(old,new,cv2.RANSAC,2.5) if len(old)>=8 else (None,None)
   if H is None or inliers.mean()<.5:
    holds+=1;max_holds=max(max_holds,holds)
    if holds>2:raise ValueError('Phone tracking is not reliable enough for screen replacement')
   else:
    candidate=H@cumulative;next_q=cv2.perspectiveTransform(original_q.astype(np.float32)[None],candidate)[0]
    area=abs(cv2.contourArea(next_q));ratio=area/abs(cv2.contourArea(original_q.astype(np.float32)))
    if not .35<ratio<2.5 or np.max(np.linalg.norm(next_q-q,axis=1))>w*.08 or not cv2.isContourConvex(next_q):raise ValueError('Phone track jumped or folded')
    q=next_q;cumulative=candidate;holds=0;tracked+=1
   points=features(gray,q)
   if points is None or len(points)<8:raise ValueError('Phone-border features became occluded')
  content=screen.copy()
  if cfg.get('confirmation')=='crown' and index/fps>=2:
   # A restrained graphic on the display, never a crown on the collectible itself.
   cx=int(sw*.84);cy=int(sh*.08);radius=max(2,int(sw*.06));gold=(55,185,239)
   crown=np.array([[cx-radius,cy-radius//2],[cx-radius//2,cy],[cx,cy-radius],[cx+radius//2,cy],[cx+radius,cy-radius//2],[cx+radius*3//4,cy+radius//2],[cx-radius*3//4,cy+radius//2]],np.int32)
   cv2.fillPoly(content,[crown],gold,lineType=cv2.LINE_AA)
  warp=cv2.getPerspectiveTransform(rect,q.astype(np.float32));replacement=cv2.warpPerspective(content,warp,(w,h))
  alpha=cv2.warpPerspective(mask_rect,warp,(w,h));alpha=np.clip(alpha,0,1)
  # Preserve bare foreground fingers connected to the hand outside the display.
  hsv=cv2.cvtColor(frame,cv2.COLOR_BGR2HSV);ycc=cv2.cvtColor(frame,cv2.COLOR_BGR2YCrCb)
  skin=(((hsv[:,:,0]<26)&(hsv[:,:,1]>30)&(hsv[:,:,2]>35))&((ycc[:,:,1]>128)&(ycc[:,:,1]<185)&(ycc[:,:,2]>70)&(ycc[:,:,2]<145))).astype(np.uint8)
  skin=cv2.morphologyEx(skin,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8));n,labels=cv2.connectedComponents(skin)
  border_ids=np.unique(labels[(alpha<.05)&(cv2.dilate((alpha>.1).astype(np.uint8),np.ones((19,19),np.uint8))>0)])
  preserve=np.isin(labels,border_ids[border_ids!=0])&(skin>0)
  alpha[preserve]=0
  result=np.clip(frame*(1-alpha[:,:,None])+replacement*alpha[:,:,None],0,255).astype(np.uint8)
  encoder.stdin.write(result.tobytes());prev=gray;index+=1
  ok,frame=cap.read()
  if not ok:break
 encoder.stdin.close();error=encoder.stderr.read();status=encoder.wait(timeout=90)
 if status:raise RuntimeError(error.decode()[-800:])
 if index<10 or tracked/max(1,index-1)<.9:raise ValueError('Insufficient reliable phone tracking')
except Exception:
 encoder.kill();encoder.wait();Path(target).unlink(missing_ok=True);raise
finally:cap.release()
print(json.dumps({'frames':index,'tracked_frames':tracked,'max_held_frames':max_holds,'refined_quad':(original_q/[w,h]).tolist(),'method':'edge-refined planar LK/RANSAC screen replacement with foreground skin occlusion','confirmation':cfg.get('confirmation','none')}))
'''


def stabilize_screen(film,plan,index,output,issues):
    if not any(word in issues.lower() for word in ['screen','phone','interface','profile']):return None
    from PIL import Image,ImageOps
    from film_worker import image_block
    shot=plan['shots'][index];source=film.remote_media(output)
    available=subprocess.run(film.dark_args('test -x /home/%s/.local/share/jarvis-film-tools/bin/python'%film.spec['dark']['user']),capture_output=True,timeout=15)
    if available.returncode:return None
    with Image.open(film.root/('scene-%03d.png'%(index+1))) as image:plate=ImageOps.fit(image.convert('RGB'),(1280,704))
    buf=io.BytesIO();plate.save(buf,format='PNG');data=buf.getvalue()
    direction=film.claude('Inspect this approved opening. Can its ONE visible phone display be safely replaced as a flat plane while retaining the live actor/hand motion? '
        'Return {"usable":false} if there is no clear phone, several ambiguous displays, gloves crossing the display, major display occlusion, or the beat requires changing/scrolling the entire interface. '
        'Otherwise return {"usable":true,"quad":[[x,y],[x,y],[x,y],[x,y]],"confirmation":"none"}. Quad is the four INNER DISPLAY corners, excluding bezel, clockwise from top-left, normalized to this image. '
        'A static collectible image should stay unchanged while the phone moves. Use confirmation:"crown" ONLY when this Drop Assassin shot saves a figure to Hit List and calls for its gold crown confirmation; it will appear in the top display header, never on the figure. Do not invent another UI action. '
        '\nUSER STORY: '+film.spec['brief']+'\nNARRATIVE BEAT: '+shot['purpose']+'\nFAILURE: '+issues,
        image_block(data,'Approved 1280 x 704 opening; identify the inner display plane'),maximum=600)
    if direction.get('usable') is not True:return None
    try:quad=validate_quad(direction.get('quad'))
    except ValueError:return None
    # A full-frame view can confuse the image card with the whole display.
    # Refine the plane on a close crop before moving any pixels.
    xs=[p[0] for p in quad];ys=[p[1] for p in quad];dx=max(xs)-min(xs);dy=max(ys)-min(ys)
    box=(max(0,int((min(xs)-dx*.4)*1280)),max(0,int((min(ys)-dy*.35)*704)),
         min(1280,int((max(xs)+dx*.4)*1280)),min(704,int((max(ys)+dy*.35)*704)))
    close=plate.crop(box);close.thumbnail((600,760));detail=io.BytesIO();close.save(detail,format='PNG')
    refined=film.claude('Identify the FOUR corners of the ENTIRE INNER PHONE DISPLAY in this close crop, clockwise top-left, top-right, bottom-right, bottom-left. Include its top status/header area AND bottom save button/navigation area. Do not give the bounds of the collectible image card. Exclude only the outer physical bezel/case. Coordinates normalized to THIS CROP. Return {"quad":[[x,y],[x,y],[x,y],[x,y]]}; return {"quad":null} if any display corner is outside the crop or ambiguous.',
        image_block(detail.getvalue(),'Close view for exact display geometry'),maximum=300)
    try:
        local=validate_quad(refined.get('quad'))
        quad=validate_quad([[(box[0]+p[0]*(box[2]-box[0]))/1280,(box[1]+p[1]*(box[3]-box[1]))/704] for p in local])
    except ValueError:return None
    confirmation=direction.get('confirmation','none')
    if confirmation not in ['none','crown']:return None
    if confirmation=='crown' and not any(x in shot['purpose'].lower() for x in ['hit list','hitlist','save']):return None
    uploaded=film.upload(data,'jarvis-screen-plate-'+hashlib.sha256(data).hexdigest()[:20]+'.png')
    if Path(uploaded).is_absolute() or '..' in Path(uploaded).parts:raise ValueError('Invalid screen plate path')
    identity=hashlib.sha256(json.dumps([source,hashlib.sha256(data).hexdigest(),quad,confirmation,tracking_script()],sort_keys=True).encode()).hexdigest()[:16]
    folder='jarvis-films/'+film.client;name='shot-%03d-screen-%s.mp4'%(index+1,identity)
    cfg={'source':source,'target':'/home/%s/ComfyUI/output/'%film.spec['dark']['user']+folder+'/'+name,
         'plate':'/home/%s/ComfyUI/input/'%film.spec['dark']['user']+uploaded,'quad':quad,'confirmation':confirmation}
    code='import base64,json;cfg=json.loads(base64.b64decode(%r));exec(base64.b64decode(%r))'%(base64.b64encode(json.dumps(cfg).encode()).decode(),base64.b64encode(tracking_script().encode()).decode())
    film.progress('Tracking the reference screen through shot %s without changing actor motion'%(index+1),'video',index)
    command='/home/%s/.local/share/jarvis-film-tools/bin/python -c '%film.spec['dark']['user']+shlex.quote(code)
    result=subprocess.run(film.dark_args(command),capture_output=True,timeout=180)
    if result.returncode:
        (film.root/('shot-%03d-screen-vfx-error.txt'%(index+1))).write_text(result.stderr.decode(errors='replace')[-1200:])
        return None
    metadata=dict(json.loads(result.stdout),quad=quad)
    (film.root/('shot-%03d-screen-vfx.json'%(index+1))).write_text(json.dumps(metadata,indent=2))
    return {'filename':name,'subfolder':folder,'type':'output'},metadata
