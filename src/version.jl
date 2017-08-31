# Version management

"""
    version()

Returns the CUDA version as reported by the driver.
"""
function version()
    version_ref = Ref{Cint}()
    @apicall(:cuDriverGetVersion, (Ref{Cint},), version_ref)

    major = version_ref[] ÷ 1000
    minor = mod(version_ref[], 100) ÷ 10

    return VersionNumber(major, minor)
end
