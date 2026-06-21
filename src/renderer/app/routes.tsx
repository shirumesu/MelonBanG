import { Navigate, Route, Routes } from "react-router-dom";
import { useAppState } from "./AppStateProvider";
import { AppShell } from "./shell/AppShell";
import { WindowFrame } from "./shell/WindowFrame";
import { SignInRoute } from "../features/auth/SignInRoute";
import { HomeRoute } from "../features/home/HomeRoute";
import { TrackingRoute } from "../features/tracking/TrackingRoute";
import { SubjectRoute } from "../features/subject/SubjectRoute";
import { ScheduleRoute } from "../features/schedule/ScheduleRoute";
import { CacheRoute } from "../features/cache/CacheRoute";
import { PlayerRoute } from "../features/player/PlayerRoute";
import { SettingsRoute } from "../features/settings/SettingsRoute";

export function AppRouter() {
  const { session, isBootstrapping } = useAppState();

  if (isBootstrapping) {
    return (
      <WindowFrame>
        <div className="grid h-full place-items-center">
          <div className="border-mint-100 border-t-mint-400 size-10 animate-spin rounded-full border-[3px]" />
        </div>
      </WindowFrame>
    );
  }

  if (!session) {
    return <SignInRoute />;
  }

  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route index element={<Navigate to="/home" replace />} />
        <Route path="/home" element={<HomeRoute />} />
        <Route path="/tracking" element={<TrackingRoute />} />
        <Route path="/subject/:subjectId" element={<SubjectRoute />} />
        <Route path="/schedule" element={<ScheduleRoute />} />
        <Route path="/cache" element={<CacheRoute />} />
      </Route>
      <Route path="/settings" element={<SettingsRoute />} />
      <Route path="/player" element={<PlayerRoute />} />
      <Route path="*" element={<Navigate to="/home" replace />} />
    </Routes>
  );
}
