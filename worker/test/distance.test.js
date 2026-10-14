import { test } from 'node:test';
import assert from 'node:assert/strict';
import { distanceMeters, rawDistanceMeters } from '../src/distance.js';
const point = (x,y) => ({lat:30+y/111194.92664455874, lon:-95+x/(111194.92664455874*Math.cos(Math.PI/6))});
const close = (actual, expected, tolerance=0.1) => assert.ok(Math.abs(actual-expected)<tolerance, `${actual} vs ${expected}`);
test('empty and single fixes have zero distance',()=>{close(distanceMeters([]),0);close(distanceMeters([point(0,0)]),0);});
test('straight walk with 2m sideways GPS noise removes zigzag inflation',()=>{
 const points=Array.from({length:201},(_,i)=>point(i*5,i===0||i===200?0:(i%2?2:-2)));
 close(distanceMeters(points),1000,0.2);
 assert.ok(rawDistanceMeters(points)>1200);
 assert.equal(points.length,201);
});
test('90 degree corner is preserved',()=>close(distanceMeters([point(0,0),point(50,0),point(100,0),point(100,50),point(100,100)]),200,0.2));
test('out-and-back reversal is preserved',()=>close(distanceMeters([point(0,0),point(50,0),point(100,0),point(50,0),point(0,0)]),200,0.2));
test('closed square loop preserves full distance',()=>close(distanceMeters([point(0,0),point(100,0),point(100,100),point(0,100),point(0,0)]),400,0.2));
test('stationary small GPS cloud is suppressed',()=>close(distanceMeters([point(0,0),point(1,1),point(-1,-1),point(0,0)]),0));
test('endpoint and short walk remain counted',()=>close(distanceMeters([point(0,0),point(1,0)]),1));
test('gentle curved path is kept within reasonable distance error',()=>{
 const p=Array.from({length:101},(_,i)=>point(100*Math.sin(i*Math.PI/200),100*(1-Math.cos(i*Math.PI/200))));
 assert.ok(distanceMeters(p)>150); assert.ok(distanceMeters(p)<=rawDistanceMeters(p)+1e-6);
});
