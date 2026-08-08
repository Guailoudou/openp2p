import common from '@ohos.app.ability.common';
import { fileIo, picker } from '@kit.CoreFileKit';

const LOG_FILE = 'log/openp2p.log';
const EXPORT_FILE_NAME = 'openp2p.log';

export class LogExportService {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async export(): Promise<boolean> {
    const sourcePath = `${this.context.filesDir}/${LOG_FILE}`;
    if (!fileIo.accessSync(sourcePath)) {
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

    const sourceFile = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
    try {
      const destinationFile = fileIo.openSync(result[0],
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.copyFileSync(sourceFile.fd, destinationFile.fd);
      } finally {
        fileIo.closeSync(destinationFile.fd);
      }
    } finally {
      fileIo.closeSync(sourceFile.fd);
    }
    return true;
  }
}
