# Manage-UserLOA config. Copy to $env:ProgramData\Manage-UserLOA\config.psd1
# (or anywhere, then pass -ConfigPath or set MANAGE_USERLOA_CONFIG) and edit
# the placeholder values for your environment. Never put secrets in this file.
@{
    # Disabled users are moved here during LOA.
    LOAOUDistinguishedName = 'OU=Users on Temporary Leave,OU=Corporate,DC=yourdomain,DC=com'

    # All AD reads/writes are pinned to this DC for consistent results.
    DomainController       = 'YOURDC.yourdomain.com'

    # Stores the user's original parent OU for End-UserLOA. Check that this
    # attribute is not already in use in your environment (for example, by
    # licence automation or an HR sync) before deploying. Any free
    # extensionAttribute1 to extensionAttribute15 works.
    OUStashAttribute       = 'extensionAttribute10'
}
