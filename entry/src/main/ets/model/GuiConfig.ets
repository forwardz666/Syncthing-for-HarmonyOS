export interface GuiConfig {
  enabled: boolean;
  address: string;
  user: string;
  password: string;
  authMode: string;
  useTLS: boolean;
  apiKey: string;
  theme: string;
  debugging: boolean;
  insecureSkipHostcheck: boolean;
  insecureAdminAccess: boolean;
  rawUnixSocketPermissions: string;
}
