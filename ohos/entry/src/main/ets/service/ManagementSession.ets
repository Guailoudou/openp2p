import { ManagementCredentials, ManagementUserProfile, RegisterRequest } from '../model/ManagementModels';
import { ManagementApiService } from './ManagementApiService';
import { ManagementCredentialStore } from './ManagementCredentialStore';

export class ManagementSession {
  private static instance: ManagementSession = new ManagementSession();
  readonly api: ManagementApiService = new ManagementApiService();
  private store: ManagementCredentialStore = new ManagementCredentialStore();
  private username: string = '';
  private openP2PToken: string = '';
  private lastError: string = '';
  private profile: ManagementUserProfile = {};

  static getInstance(): ManagementSession {
    return ManagementSession.instance;
  }

  getUsername(): string {
    return this.username;
  }

  getOpenP2PToken(): string {
    return this.openP2PToken;
  }

  getLastError(): string {
    return this.lastError;
  }

  getProfile(): ManagementUserProfile {
    return this.profile;
  }

  async initialize(): Promise<boolean> {
    const credentials = await this.store.loadCredentials();
    if (!credentials) {
      this.username = '';
      this.openP2PToken = '';
      this.lastError = '';
      this.profile = {};
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

  async registerAndLogin(username: string, password: string, phone: string, email: string): Promise<boolean> {
    const credentials: ManagementCredentials = {
      username: username.trim(),
      password: password
    };
    const request: RegisterRequest = {
      user: credentials.username,
      password: credentials.password,
      phone: phone.trim(),
      email: email.trim()
    };
    await this.store.saveCredentials(credentials);
    this.username = credentials.username;
    try {
      const token = await this.api.register(request);
      return this.loadProfileAndSaveToken(token);
    } catch (error) {
      await this.resetAuthentication(error);
      return false;
    }
  }

  async clear(): Promise<void> {
    await this.store.clear();
    this.username = '';
    this.openP2PToken = '';
    this.lastError = '';
    this.profile = {};
    this.api.setToken('');
  }

  private async loginAndSaveToken(credentials: ManagementCredentials): Promise<boolean> {
    try {
      const token = await this.api.login(credentials);
      return this.loadProfileAndSaveToken(token);
    } catch (error) {
      await this.resetAuthentication(error);
      return false;
    }
  }

  private async loadProfileAndSaveToken(token: string): Promise<boolean> {
    this.api.setToken(token);
    this.profile = await this.api.getUserProfile();
    this.openP2PToken = this.profile.token ? this.profile.token : '';
    await this.store.saveToken(token);
    this.lastError = '';
    return true;
  }

  private async resetAuthentication(error: Object): Promise<void> {
    this.openP2PToken = '';
    this.lastError = this.errorMessage(error);
    this.profile = {};
    this.api.setToken('');
    await this.store.saveToken('');
  }

  private errorMessage(error: Object): string {
    const value = error as Record<string, Object>;
    const message = value['message'];
    return typeof message === 'string' && message.length > 0 ? message : String(error);
  }
}
