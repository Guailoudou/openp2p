import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ManagementCredentials } from '../model/ManagementModels';

const CREDENTIAL_ALIAS = 'openp2p_management_credentials';
const TOKEN_ALIAS = 'openp2p_management_token';
const ASSET_NOT_FOUND = 24000002;
const ASSET_ALREADY_EXISTS = 24000003;

export class ManagementCredentialStore {
  private encoder: util.TextEncoder = new util.TextEncoder();
  private decoder: util.TextDecoder = new util.TextDecoder();

  async loadCredentials(): Promise<ManagementCredentials | undefined> {
    const value = await this.load(CREDENTIAL_ALIAS);
    if (value.length === 0) {
      return undefined;
    }
    try {
      const credentials = JSON.parse(value) as ManagementCredentials;
      if (credentials.username.length === 0 || credentials.password.length === 0) {
        return undefined;
      }
      return credentials;
    } catch (_) {
      return undefined;
    }
  }

  async saveCredentials(credentials: ManagementCredentials): Promise<void> {
    await this.save(CREDENTIAL_ALIAS, JSON.stringify(credentials));
  }

  async loadToken(): Promise<string> {
    return this.load(TOKEN_ALIAS);
  }

  async saveToken(token: string): Promise<void> {
    if (token.length === 0) {
      await this.remove(TOKEN_ALIAS);
      return;
    }
    await this.save(TOKEN_ALIAS, token);
  }

  async clear(): Promise<void> {
    await this.remove(CREDENTIAL_ALIAS);
    await this.remove(TOKEN_ALIAS);
  }

  private async load(alias: string): Promise<string> {
    const query = this.createAliasQuery(alias);
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const result = await asset.query(query);
      if (result.length === 0) {
        return '';
      }
      const secret = result[0].get(asset.Tag.SECRET);
      return secret instanceof Uint8Array ? this.decoder.decodeToString(secret) : '';
    } catch (error) {
      if (this.errorCode(error) === ASSET_NOT_FOUND) {
        return '';
      }
      throw new Error(this.errorMessage(error));
    }
  }

  private async save(alias: string, value: string): Promise<void> {
    const query = this.createAliasQuery(alias);
    const attributesToUpdate: asset.AssetMap = new Map();
    attributesToUpdate.set(asset.Tag.SECRET, this.toBytes(value));
    try {
      await asset.update(query, attributesToUpdate);
      return;
    } catch (error) {
      if (this.errorCode(error) !== ASSET_NOT_FOUND) {
        throw new Error(this.errorMessage(error));
      }
    }

    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, this.toBytes(alias));
    attributes.set(asset.Tag.SECRET, this.toBytes(value));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.add(attributes);
    } catch (error) {
      if (this.errorCode(error) === ASSET_ALREADY_EXISTS) {
        await asset.update(query, attributesToUpdate);
        return;
      }
      throw new Error(this.errorMessage(error));
    }
  }

  private async remove(alias: string): Promise<void> {
    try {
      await asset.remove(this.createAliasQuery(alias));
    } catch (error) {
      if (this.errorCode(error) !== ASSET_NOT_FOUND) {
        throw new Error(this.errorMessage(error));
      }
    }
  }

  private createAliasQuery(alias: string): asset.AssetMap {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.toBytes(alias));
    return query;
  }

  private toBytes(value: string): Uint8Array {
    return this.encoder.encodeInto(value);
  }

  private errorCode(error: Object): number {
    return (error as BusinessError).code;
  }

  private errorMessage(error: Object): string {
    const businessError = error as BusinessError;
    return businessError.message.length > 0 ? businessError.message : String(error);
  }
}
