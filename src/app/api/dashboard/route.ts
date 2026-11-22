import { requireStaff,routeError } from "@/lib/server/auth";import { adminClient } from "@/lib/server/supabase";
export async function GET(){try{const staff=await requireStaff();const{data,error}=await adminClient().rpc("dashboard_summary_v1",{p_staff_id:staff.id,p_admin:staff.role==="admin"});if(error)throw error;return Response.json(data)}catch(e){return routeError(e)}}
