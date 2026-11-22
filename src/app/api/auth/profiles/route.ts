import { adminClient } from "@/lib/server/supabase";import { routeError } from "@/lib/server/auth";
export async function GET(){try{const{data,error}=await adminClient().from("users").select("id,name,role,active").eq("active",true).order("name");if(error)throw error;return Response.json({staff:data??[],setup_required:!data?.length})}catch(e){return routeError(e)}}
