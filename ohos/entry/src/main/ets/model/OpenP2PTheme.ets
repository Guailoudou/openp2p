import { CustomColors, CustomTheme } from '@kit.ArkUI';

export const DEFAULT_THEME_COLOR: string = '#0A59F7';

class OpenP2PThemeColors implements CustomColors {
  brand: ResourceColor;
  fontEmphasize: ResourceColor;
  iconEmphasize: ResourceColor;
  iconSubEmphasize: ResourceColor;
  backgroundEmphasize: ResourceColor;
  compBackgroundEmphasize: ResourceColor;
  compEmphasizeSecondary: ResourceColor;
  interactiveFocus: ResourceColor;
  interactiveActive: ResourceColor;

  constructor(color: string) {
    this.brand = color;
    this.fontEmphasize = color;
    this.iconEmphasize = color;
    this.iconSubEmphasize = `#66${color.substring(1)}`;
    this.backgroundEmphasize = color;
    this.compBackgroundEmphasize = color;
    this.compEmphasizeSecondary = `#33${color.substring(1)}`;
    this.interactiveFocus = color;
    this.interactiveActive = color;
  }
}

export class OpenP2PTheme implements CustomTheme {
  colors: OpenP2PThemeColors;

  constructor(color: string) {
    this.colors = new OpenP2PThemeColors(color);
  }
}
