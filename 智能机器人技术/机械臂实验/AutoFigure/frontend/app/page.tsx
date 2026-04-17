import { redirect } from "next/navigation"

export default function Home() {
    // Server-side redirect to AutoFigure page - more reliable than client-side redirect
    redirect("/autofigure")
}
