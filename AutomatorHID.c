# Author: Harry Moss
# Date: 02/09/2024

#include "main.h"

extern USBD_HandleTypeDef hUsbDeviceFS;

#define KEY_NONE        0x00
#define KEY_ENTER       0x28
#define KEY_TAB         0x2B
#define KEY_SPACE       0x2C
#define KEY_DOWN        0x51

#define MODIFIER_NONE   0x00

#define BUTTON_PRESSED  HAL_GPIO_ReadPin(B1_GPIO_Port, B1_Pin) == GPIO_PIN_SET

static uint8_t triggered = 0;

void send_hid_key(uint8_t modifier, uint8_t keycode)
{
    uint8_t report[8] = {0};

    report[0] = modifier;
    report[2] = keycode;

    USBD_HID_SendReport(&hUsbDeviceFS, report, sizeof(report));
    HAL_Delay(80);

    memset(report, 0, sizeof(report));
    USBD_HID_SendReport(&hUsbDeviceFS, report, sizeof(report));
    HAL_Delay(80);
}

void send_key_sequence()
{
    /*
        Example sequence:

        TAB
        TAB
        ENTER
        wait
        ENTER

        Adjust based on exact provisioning workflow.
    */

    HAL_Delay(3000);

    send_hid_key(MODIFIER_NONE, KEY_TAB);
    HAL_Delay(300);

    send_hid_key(MODIFIER_NONE, KEY_TAB);
    HAL_Delay(300);

    send_hid_key(MODIFIER_NONE, KEY_ENTER);
    HAL_Delay(1500);

    send_hid_key(MODIFIER_NONE, KEY_ENTER);
    HAL_Delay(1000);
}

int main(void)
{
    HAL_Init();

    SystemClock_Config();

    MX_GPIO_Init();
    MX_USB_DEVICE_Init();

    while (1)
    {
        if (BUTTON_PRESSED && !triggered)
        {
            HAL_Delay(50);

            if (BUTTON_PRESSED)
            {
                triggered = 1;

                send_key_sequence();
            }
        }

        if (!BUTTON_PRESSED)
        {
            triggered = 0;
        }

        HAL_Delay(10);
    }
}