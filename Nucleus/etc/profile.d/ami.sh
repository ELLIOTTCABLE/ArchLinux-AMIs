if [ ! -f /usr/aws/ec2/.introduced ]; then
  
cat <<'INTRODUCTION'
-----------------------------------------------------------------------------
[40m               [96m,[36m      [90;1m                 _      [96;22m _ _                          
              [96m/#\[36m     [90;1m   __ _ _ __ ___| |__   [96;22m| (_)_ __  _   ___  __        
             [96m,###\[36m    [90;1m  / _` | '__/ __| '_ \  [96;22m| | | '_ \| | | \ \/ /        
            [96m/#####\[36m   [90;1m | (_| | | | (__| | | | [96;22m| | | | | | |_| |>  <         
           [96m/##[36m,-,##\[36m   [90;1m \__,_|_|  \___|_| |_| [96;22m|_|_|_| |_|\__,_/_/\_\        
          [36m/##(   )##`                                                       
         [36m/#.--   --.#\[97m    A simple, elegant gnu/linux distribution.         
        [36m/`           `\                                                     [0m
 
     Please note, there are things you need to know about this machine
     before you start using it! You can view the README for the
     ArchLinux-AMIs project on GitHub, available at the following URL:

                [4;94mhttp://github.com/elliottcable/ArchLinux-AMIs/[0m

     Most importantly,
     - You [1mshould not[0m re-bundle this AMI without reading the re-bundling
       instructions in the above-linked README
     - [1;31mAll access is allowed[0m by /etc/hosts.deny, so your EC2 security
       group should be configured as restrictively as possible!
-----------------------------------------------------------------------------
INTRODUCTION
  
  mkdir -p /usr/aws/ec2/ && touch /usr/aws/ec2/.introduced
fi

