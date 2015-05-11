Code snippet to create/update hash files for salt winrepo:

```powershell
$bucket = "systemprep-repo"
$key = "windows/"
$savepath = "."

# Download the files from the s3 bucket
$s3objects = Get-S3Object -BucketName $bucket -Key $key | where { $_.Key[-1] -ne "/" }
$s3objects | % { Read-S3Object -BucketName $bucket -Key $_.Key -File "${savepath}\$(${_}.Key.replace('/','\'))" }

# Generate hashes for all files
$orig_files = Get-Item -Path "${savepath}\$(${key}.replace('/','\'))" | Get-ChildItem -Recurse -File 
$hashes = $orig_files | Where { $_.Name -notmatch "md5$|sha512$|sha384$|sha256$|sha1$" } | Get-FileHash -Algorithm SHA512

# Write hashes to the same directory as the file
$hashes | % { "$($_.Hash.ToLower()) $($_.Path.Split('\')[-1])" | Set-Content "$($_.Path).$($_.Algorithm)" }

# Upload hash files to the s3 bucket
$hash_files = Get-Item -Path "${savepath}\$(${key}.replace('/','\'))" | Get-ChildItem -Recurse -File | where { $_.Name -match "md5$|sha512$|sha384$|sha256$|sha1$" }
$hash_files | % { Write-S3Object -BucketName $bucket -Key $($_.FullName.Split('\')[($_.FullName.Split('\').Indexof("windows"))..($_.FullName.Split('\').Length)] -join '/') -File $_.FullName }
```
