Pod::Spec.new do |spec|

  spec.name                     = 'Zerk'
  
  spec.version                  = '0.1.1'
  
  spec.summary                  = 'Easily store, restore and inject dependencies'
  
  spec.homepage                 = 'https://github.com/ofgokce/Zerk'
  
  spec.license                  = { :type => 'MIT', :file => 'LICENSE' }
  
  spec.author                   = { 'Ömer Faruk Gökce' => 'mail@ofgokce.com' }
  
  spec.source                   = { :git => 'https://github.com/ofgokce/Zerk.git', :tag => spec.version.to_s }
  
  spec.social_media_url         = 'https://linkedin.com/in/ofgokce/'
  
  spec.swift_version            = '5.0'

  spec.ios.deployment_target    = '9.0'

  spec.source_files             = 'Sources/Zerk/**/*'
  
end
