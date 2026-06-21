import { Navigate, Route, Routes } from "react-router-dom";
import { useAppState } from "./AppStateProvider";
import { AppShell } from "./shell/AppShell";
import { SignInRoute } from "../features/auth/SignInRoute";
import { HomeRoute } from "../features/home/HomeRoute";
import { TrackingRoute } from "../features/tracking/TrackingRoute";
import { SubjectRoute } from "../features/tracking/SubjectRoute";
import { SearchRoute } from "../features/tracking/SearchRoute";
import { SettingsRoute } from "../features/settings/SettingsRoute";

export function AppRouter() {
  const { session, isBootstrapping } = useAppState();

  if (isBootstrapping) {
    return (
      <div className="text-muted-foreground flex h-full items-center justify-center text-sm">
        Loading melonbang…
      </div>
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
        <Route path="/search" element={<SearchRoute />} />
        <Route path="/subject/:subjectId" element={<SubjectRoute />} />
        <Route path="/settings" element={<SettingsRoute />} />
      </Route>
      <Route path="*" element={<Navigate to="/home" replace />} />
    </Routes>
  );
}
