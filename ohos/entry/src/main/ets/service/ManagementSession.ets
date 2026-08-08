import { ManagementCredentials } from '../model/ManagementModels';
import { ManagementApiService } from './ManagementApiService';
import { ManagementCredentialStore } from './ManagementCredentialStore';

export class ManagementSession {
  private static instance: ManagementSession = new ManagementSession();
  readonly api: ManagementApiService = new ManagementApiService();
  private store: ManagementCredentialStore = new ManagementCredentialStore();
  private username: string = '';

  static getInstance(): ManagementSession {
    return ManagementSession.instance;
  }

  getUsername(): string {
    return this.username;
  }

  async initialize(): Promise<boolean> {
    const credentials = await this.store.loadCredentials();
    if (!credentials) {
      this.username = '';
      this.api.setToken('');
      await this.store.saveToken('');
      return false;
    }
    this.username = credentials.username;
    return this.loginAndSaveToken(credentials);
  }

  async saveCredentialsAndLogin(username: string, password: string): Promise<boolean> {
    const credentials: ManagementCredentials = {
      username: username.trim(),
      password: password
    };
    await this.store.saveCredentials(credentials);
    this.username = credentials.username;
    return this.loginAndSaveToken(credentials);
  }

  async clear(): Promise<void> {
    await this.store.clear();
    this.username = '';
    this.api.setToken('');
  }

  private async loginAndSaveToken(credentials: ManagementCredentials): Promise<boolean> {
    try {
      const token = await this.api.login(credentials);
      this.api.setToken(token);
      await this.store.saveToken(token);
      return true;
    } catch (_) {
      this.api.setToken('');
      await this.store.saveToken('');
      return false;
    }
  }
}
