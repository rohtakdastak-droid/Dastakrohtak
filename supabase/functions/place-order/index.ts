// Server-only routing and transactional checkout. Never falls back to client pricing.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
Deno.serve(async req=>{
 if(req.method==='OPTIONS') return reply({});
 if(req.method!=='POST') return reply({error:'method_not_allowed'},405);
 try {
  const token=(req.headers.get('Authorization')??'').replace(/^Bearer /,'');
  if(new URL(req.url).searchParams.get('health')==='1'){
   if(!Deno.env.get('PUSH_WEBHOOK_TOKEN')||token!==Deno.env.get('PUSH_WEBHOOK_TOKEN')) return reply({error:'Unauthorized'},401);
   const key=[Deno.env.get('GOOGLE_MAPS_API_KEY'),Deno.env.get('GOOGLE_ROUTES_API_KEY')].map(value=>value?.match(/AIza[A-Za-z0-9_-]{35}/)?.[0]).find(Boolean);
   if(!key) return reply({routing_ready:false,reason:'missing_key'},503);
   const check=await fetch('https://routes.googleapis.com/directions/v2:computeRoutes',{method:'POST',signal:AbortSignal.timeout(15000),headers:{'Content-Type':'application/json','X-Goog-Api-Key':key,'X-Goog-FieldMask':'routes.distanceMeters'},body:JSON.stringify({origin:{location:{latLng:{latitude:28.8955,longitude:76.6066}}},destination:{location:{latLng:{latitude:28.901,longitude:76.613}}},travelMode:'DRIVE',routingPreference:'TRAFFIC_UNAWARE'})});
   const result=await check.json().catch(()=>({error:{status:'NON_JSON_RESPONSE'}}));
   const ready=check.ok&&Number.isFinite(result.routes?.[0]?.distanceMeters);
   return reply({routing_ready:ready,provider_status:check.status,reason:result.error?.status??null},ready?200:503);
  }
  const url=Deno.env.get('SUPABASE_URL')!;
  const caller=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false},global:{headers:{Authorization:`Bearer ${token}`}}});
  const {data:{user},error:authError}=await caller.auth.getUser(token);
  if(authError||!user) return reply({error:'Sign in to continue'},401);
  const input=await req.json();
  const {vendor_id,dest_address,dest_lat,dest_lng,items,customer_note,quote_only,request_id,expected_total_paise}=input;
  if(typeof vendor_id!=='string'||typeof dest_address!=='string'||dest_address.trim().length<8||dest_address.length>1000||
   !Number.isFinite(dest_lat)||!Number.isFinite(dest_lng)||Math.abs(dest_lat)>90||Math.abs(dest_lng)>180||
   !Array.isArray(items)||items.length<1||items.length>100||
   (customer_note!=null&&(typeof customer_note!=='string'||customer_note.length>1000))) return reply({error:'Invalid checkout details'},400);
  if(!quote_only&&request_id!=null&&!/^[0-9a-f-]{36}$/i.test(request_id)) return reply({error:'Invalid request ID'},400);
  const service=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  // A retry after a lost response must work even if routing is temporarily offline.
  if(!quote_only&&request_id){
   const {data:prior}=await service.from('checkout_attempts').select('order_id').eq('customer_id',user.id).eq('request_id',request_id).maybeSingle();
   if(prior?.order_id){
    // RPC validates the original request fingerprint before returning the same order.
    const {data,error}=await service.rpc('mobile_place_order',{p_customer:user.id,p_request:request_id,p_vendor:vendor_id,p_address:dest_address.trim(),p_lat:dest_lat,p_lng:dest_lng,p_distance:0,p_items:items,p_note:customer_note??null,p_expected:expected_total_paise??null});
    return error?reply({error:error.message},400):reply({order_id:data});
   }
  }
  const {data:v,error:vError}=await caller.from('vendors').select('latitude,longitude,is_active,service_radius_km').eq('id',vendor_id).single();
  if(vError||!v?.is_active) return reply({error:'Store unavailable'},400);
  // Haversine straight-line distance (used as fallback when Google Routes API key is not set).
  const haversine=(lat1:number,lng1:number,lat2:number,lng2:number)=>{const r=6371;const toRad=(x:number)=>x*Math.PI/180;const dLat=toRad(lat2-lat1);const dLng=toRad(lng2-lng1);const a=Math.sin(dLat/2)**2+Math.cos(toRad(lat1))*Math.cos(toRad(lat2))*Math.sin(dLng/2)**2;return r*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a));};
  const key=[Deno.env.get('GOOGLE_MAPS_API_KEY'),Deno.env.get('GOOGLE_ROUTES_API_KEY')].map(value=>value?.match(/AIza[A-Za-z0-9_-]{35}/)?.[0]).find(Boolean);
  let km:number;
  let provider='haversine';
  if(key){
   const routeResponse=await fetch('https://routes.googleapis.com/directions/v2:computeRoutes',{method:'POST',signal:AbortSignal.timeout(15000),headers:{'Content-Type':'application/json','X-Goog-Api-Key':key,'X-Goog-FieldMask':'routes.distanceMeters'},body:JSON.stringify({origin:{location:{latLng:{latitude:Number(v.latitude),longitude:Number(v.longitude)}}},destination:{location:{latLng:{latitude:dest_lat,longitude:dest_lng}}},travelMode:'DRIVE',routingPreference:'TRAFFIC_UNAWARE'})});
   if(routeResponse.ok){
    const route=await routeResponse.json();
    const meters=route.routes?.[0]?.distanceMeters;
    if(Number.isFinite(meters)&&meters>=0){
     km=meters/1000;
     provider='google';
    } else {
     // Google returned no route — fall back to haversine with a road-detour multiplier
     km=haversine(Number(v.latitude),Number(v.longitude),dest_lat,dest_lng)*1.3;
    }
   } else {
    km=haversine(Number(v.latitude),Number(v.longitude),dest_lat,dest_lng)*1.3;
   }
  } else {
   // No Google key configured — use haversine with 1.3x road-detour multiplier
   km=haversine(Number(v.latitude),Number(v.longitude),dest_lat,dest_lng)*1.3;
  }
  if(km>Number(v.service_radius_km)) return reply({error:'Address is outside this store’s delivery area'},422);
  if(quote_only){
   const {data,error}=await service.rpc('resolve_checkout',{p_vendor_id:vendor_id,p_items:items,p_distance:km});
   return error?reply({error:error.message},400):reply({...data,distance_km:km,provider});
  }
  const {data,error}=await service.rpc('mobile_place_order',{p_customer:user.id,p_request:request_id??crypto.randomUUID(),p_vendor:vendor_id,p_address:dest_address.trim(),p_lat:dest_lat,p_lng:dest_lng,p_distance:km,p_items:items,p_note:customer_note??null,p_expected:expected_total_paise??null});
  return error?reply({error:error.message},400):reply({order_id:data,distance_km:km,provider});
 }catch(error){return reply({error:'Checkout temporarily unavailable. Retry the same attempt.', ...(new URL(req.url).searchParams.get('health')==='1'?{failure_type:error instanceof Error?error.name:'Unknown', failure_category:error instanceof Error?(/header|ByteString|character/i.test(error.message)?'invalid_header':/fetch|connect|dns/i.test(error.message)?'network':/AbortSignal|timeout/i.test(error.message)?'timeout_api':'other'):'other'}:{})},503);}
});
