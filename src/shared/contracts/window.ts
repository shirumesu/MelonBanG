export interface WindowControlsBridge {
  minimize(): void;
  toggleMaximize(): void;
  close(): void;
  isMaximized(): Promise<boolean>;
  onMaximizeChange(callback: (maximized: boolean) => void): () => void;
}
