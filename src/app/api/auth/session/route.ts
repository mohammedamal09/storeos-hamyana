import { currentStaff,routeError } from "@/lib/server/auth";export async function GET(){try{return Response.json({user:await currentStaff()})}catch(e){return routeError(e)}}
