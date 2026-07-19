# powershell-profile 

Collects basic Windows PC specifications and creates a Discord-ready report.

.DESCRIPTION
    Collects:
    - Windows version
    - Computer manufacturer and model
    - CPU
    - GPU(s)
    - Installed RAM
    - Physical storage drives (SSD/HDD/NVMe when detectable)
    - Original Windows installation date
    - PowerShell version

  The formatted report is:
    - Printed in the console
    - Saved to a text file on the Desktop
    - Copied to the clipboard

.NOTES
    This script intentionally avoids collecting sensitive information such as:
    - Windows product keys
    - Serial numbers
    - IP addresses
    - MAC addresses
    - User files
