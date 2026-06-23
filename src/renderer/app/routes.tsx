import { lazy, Suspense } from "react";
import type { ReactNode } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { useAppState } from "./AppStateProvider";
import { AppShell } from "./shell/AppShell";
import { WindowFrame } from "./shell/WindowFrame";
import { SignInRoute } from "../features/auth/SignInRoute";
import { HomeRoute } from "../features/home/HomeRoute";
import { TrackingRoute } from "../features/tracking/TrackingRoute";

const SearchRoute = lazy(() =>
  import("../features/tracking/SearchRoute").then((module) => ({ default: module.SearchRoute }))
);
const SubjectRoute = lazy(() =>
  import("../features/subject/SubjectRoute").then((module) => ({ default: module.SubjectRoute }))
);
const ScheduleRoute = lazy(() =>
  import("../features/schedule/ScheduleRoute").then((module) => ({ default: module.ScheduleRoute }))
);
const CacheRoute = lazy(() =>
  import("../features/cache/CacheRoute").then((module) => ({ default: module.CacheRoute }))
);
const PlayerRoute = lazy(() =>
  import("../features/player/PlayerRoute").then((module) => ({ default: module.PlayerRoute }))
);
const SettingsRoute = lazy(() =>
  import("../features/settings/SettingsRoute").then((module) => ({ default: module.SettingsRoute }))
);

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
    return (
      <Routes>
        <Route path="/signin" element={<SignInRoute />} />
        <Route path="*" element={<Navigate to="/signin" replace />} />
      </Routes>
    );
  }

  return (
    <Routes>
      <Route path="/signin" element={<Navigate to="/home" replace />} />
      <Route element={<AppShell />}>
        <Route index element={<Navigate to="/home" replace />} />
        <Route path="/home" element={<HomeRoute />} />
        <Route path="/tracking" element={<TrackingRoute />} />
        <Route path="/search" element={deferRoute(<SearchRoute />)} />
        <Route path="/subject/:subjectId" element={deferRoute(<SubjectRoute />)} />
        <Route path="/schedule" element={deferRoute(<ScheduleRoute />)} />
        <Route path="/cache" element={deferRoute(<CacheRoute />)} />
      </Route>
      <Route path="/settings" element={deferRoute(<SettingsRoute />)} />
      <Route path="/player" element={deferRoute(<PlayerRoute />)} />
      <Route path="*" element={<Navigate to="/home" replace />} />
    </Routes>
  );
}

function deferRoute(element: ReactNode): ReactNode {
  return <Suspense fallback={<RouteFallback />}>{element}</Suspense>;
}

function RouteFallback() {
  return (
    <div className="grid h-full min-h-[240px] place-items-center">
      <div className="border-mint-100 border-t-mint-400 size-8 animate-spin rounded-full border-[3px]" />
    </div>
  );
}
