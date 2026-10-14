// Distance-only Ramer–Douglas–Peucker simplification. Raw track is retained.
// Fixed 3 m tolerance is intentionally independent of the Apple Watch result.
const R = 6371000;
const rad = d => d * Math.PI / 180;
export function meters(a, b) {
  const s = Math.sin(rad(b.lat-a.lat)/2)**2 + Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(rad(b.lon-a.lon)/2)**2;
  return 2*R*Math.asin(Math.sqrt(Math.min(1, Math.max(0, s))));
}
function deviation(p, a, b) {
  const scale = Math.cos(rad(a.lat));
  const x = rad(p.lon-a.lon)*R*scale, y = rad(p.lat-a.lat)*R;
  const bx = rad(b.lon-a.lon)*R*scale, by = rad(b.lat-a.lat)*R;
  const t = bx*bx+by*by > 0 ? Math.max(0, Math.min(1, (x*bx+y*by)/(bx*bx+by*by))) : 0;
  return Math.hypot(x-t*bx, y-t*by);
}
export function distanceMeters(points, tolerance = 3) {
  if (points.length < 2) return 0;
  const keep = new Set([0, points.length-1]);
  const stack = [[0, points.length-1]];
  while (stack.length) {
    const [a,b] = stack.pop();
    let best = tolerance, index = -1;
    for (let i=a+1; i<b; i++) {
      const v = deviation(points[i],points[a],points[b]);
      if (v > best) { best=v; index=i; }
    }
    if (index >= 0) { keep.add(index); stack.push([a,index],[index,b]); }
  }
  const indices = [...keep].sort((a,b)=>a-b);
  let total=0;
  for (let i=1; i<indices.length; i++) total += meters(points[indices[i-1]],points[indices[i]]);
  return total;
}
export function rawDistanceMeters(points) {
  return points.slice(1).reduce((s,p,i)=>s+meters(points[i],p),0);
}
