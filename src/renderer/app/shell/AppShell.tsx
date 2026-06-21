import { Outlet } from "react-router-dom";
import { Sidebar } from "./Sidebar";
import { WindowFrame } from "./WindowFrame";

export function AppShell() {
  return (
    <WindowFrame>
      <div className="grid h-full min-h-0 grid-cols-[236px_1fr]">
        <Sidebar />
        <main className="flex min-h-0 flex-col">
          <Outlet />
        </main>
      </div>
    </WindowFrame>
  );
}
