/**
 * Shared single-line text input used by Device/Folder detail pages.
 *
 * Keeps the input background, padding, radius, border, hover and focus styles
 * consistent between the device and folder editors, and adapts to dark mode
 * through the same $r('app.color.*') resources used by the rest of the app.
 */
@Component
export struct AppTextInput {
  @Prop text: string = '';
  @Prop placeholder: string = '';
  @Prop inputHeight: number = 44;
  @Prop inputFontSize: number = 15;
  @Prop readOnly: boolean = false;
  onChange?: (value: string) => void = undefined;
  onSubmit?: () => void = undefined;

  @State isHovered: boolean = false;
  @State isFocused: boolean = false;

  build() {
    TextInput({ text: this.text, placeholder: this.placeholder })
      .height(this.inputHeight)
      .fontSize(this.inputFontSize)
      .fontColor($r('app.color.text_primary'))
      .placeholderColor($r('app.color.text_tertiary'))
      .enabled(!this.readOnly)
      .padding({ left: 12, right: 12, top: 0, bottom: 0 })
      .backgroundColor(this.isFocused ? $r('app.color.input_focus_background') :
        (this.isHovered ? $r('app.color.input_hover_background') : $r('app.color.input_background')))
      .borderRadius(8)
      .border({
        width: this.isFocused ? 2 : 1,
        color: this.isFocused ? $r('app.color.input_focus_border') :
          (this.isHovered ? $r('app.color.input_hover_border') : $r('app.color.input_border'))
      })
      .onHover((isHover: boolean) => {
        this.isHovered = isHover;
      })
      .onFocus(() => {
        this.isFocused = true;
      })
      .onBlur(() => {
        this.isFocused = false;
      })
      .onChange((value: string) => {
        if (this.onChange !== undefined) {
          this.onChange(value);
        }
      })
      .onSubmit(() => {
        if (this.onSubmit !== undefined) {
          this.onSubmit();
        }
      })
  }
}
