import { Toaster } from "sonner";
import { AppRouter } from "./routes";
import { AppStateProvider } from "./AppStateProvider";
import { ThemeProvider } from "./ThemeProvider";

export function App() {
  return (
    <AppStateProvider>
      <ThemeProvider>
        <AppRouter />
        <Toaster richColors position="top-right" />
      </ThemeProvider>
    </AppStateProvider>
  );
}
