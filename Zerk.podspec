#
# Be sure to run `pod lib lint Zerk.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Zerk'
  s.version          = '0.1.0'
  s.summary          = 'Easily store and restore dependencies'
  s.description      = "Zerk allows you to easily store and restore your dependencies. It removes the need for static methods and singletons. With Zerk you can ensure that your dependencies are global whilst keeping them testable. You can inject your dependencies via initializers, methods or other known ways of DI. You can also use @Injected keyword to inject as a non-stored property. Also there are other keywords for injecting only the properties or methods of your dependencies, using the cutting-edge key path feature of Swift. The dependencies are not initialized when stored, this is because Zerk stores their initializing logic when you use the storing methods. When the dependency is being called, if it hasn't been initialized before it will be initialized and only then the instance will be cached for upcoming calls."
  s.homepage         = 'https://github.com/ofgokce/Zerk'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Ömer Faruk Gökce' => 'mail@ofgokce.com' }
  s.source           = { :git => 'https://github.com/ofgokce/Zerk.git', :tag => s.version.to_s }
  s.social_media_url = 'https://linkedin.com/in/ofgokce'

  s.ios.deployment_target = '9.0'

  s.source_files = 'Sources/Zerk/**/*'
  
  # s.resource_bundles = {
  #   'Zerk' => ['Zerk/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
end
