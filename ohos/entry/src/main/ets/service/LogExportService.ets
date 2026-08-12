import common from '@ohos.app.ability.common';
import { fileIo, picker } from '@kit.CoreFileKit';

const LOG_FILES: string[] = ['log/openp2p.log', 'log/openp2p.log.0'];
const EXPORT_FILE_NAME = 'openp2p-diagnostics.log';

export class LogExportService {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async export(): Promise<boolean> {
    const availableFiles = LOG_FILES.filter((relativePath: string): boolean =>
      fileIo.accessSync(`${this.context.filesDir}/${relativePath}`));
    if (availableFiles.length === 0) {
      throw new Error('暂无可导出的日志文件');
    }

    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [EXPORT_FILE_NAME];
    options.fileSuffixChoices = ['日志文件|.log'];

    const documentPicker = new picker.DocumentViewPicker(this.context);
    const result = await documentPicker.save(options);
    if (result.length === 0) {
      return false;
    }

    let diagnostics = `OpenP2P HarmonyOS diagnostics\nGenerated: ${new Date().toISOString()}\n`;
    availableFiles.forEach((relativePath: string): void => {
      const sourcePath = `${this.context.filesDir}/${relativePath}`;
      const name = relativePath.substring(relativePath.lastIndexOf('/') + 1);
      diagnostics += `\n===== ${name} =====\n${this.maskSensitive(fileIo.readTextSync(sourcePath))}`;
    });
    let destinationFile: fileIo.File | undefined = undefined;
    try {
      destinationFile = fileIo.openSync(result[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(destinationFile.fd, diagnostics);
    } catch (error) {
      throw new Error(`Unable to write diagnostics: ${String(error)}`);
    } finally {
      if (destinationFile !== undefined) {
        try {
          fileIo.closeSync(destinationFile.fd);
        } catch (_) {
        }
      }
    }
    return true;
  }

  private maskSensitive(value: string): string {
    return value.replace(/(token|password|authorization)(\s*[:=]\s*)[^\s,;}]+/gi, '$1$2*******');
  }
}
