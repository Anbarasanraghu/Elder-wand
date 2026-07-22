' Launches the AKERIYAN backend fully hidden (no console window) at logon.
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Users\anbar\Desktop\My_Projects\Akeriyan\akeriyan_backend\start_akeriyan.ps1""", 0, False
