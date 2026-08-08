import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { asset } from '@kit.AssetStoreKit';

const TOKEN_ALIAS = 'openp2p_access_token';
const ASSET_NOT_FOUND = 24000002;
const ASSET_ALREADY_EXISTS = 24000003;

export class TokenStore {
  private encoder: util.TextEncoder = new util.TextEncoder();
  private decoder: util.TextDecoder = new util.TextDecoder();

  async load(): Promise<string> {
    const query = this.createAliasQuery();
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

  async save(token: string): Promise<void> {
    const query = this.createAliasQuery();
    const attributesToUpdate: asset.AssetMap = new Map();
    attributesToUpdate.set(asset.Tag.SECRET, this.toBytes(token));
    try {
      await asset.update(query, attributesToUpdate);
      return;
    } catch (error) {
      if (this.errorCode(error) !== ASSET_NOT_FOUND) {
        throw new Error(this.errorMessage(error));
      }
    }

    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, this.toBytes(TOKEN_ALIAS));
    attributes.set(asset.Tag.SECRET, this.toBytes(token));
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

  private createAliasQuery(): asset.AssetMap {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.toBytes(TOKEN_ALIAS));
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
