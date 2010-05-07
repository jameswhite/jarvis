package Jarvis::Persona::System;
use parent Jarvis::Persona::Base;
use AI::MegaHAL;
use POE;
use POSIX qw( setsid );
use POE::Builder;
use LWP::UserAgent;
use YAML;

sub known_personas{
    my $self=shift;
    $self->{'known_personas'} = $self->indented_yaml(<<"    ...");
    ---
     - name: crunchy
       persona:
         class: Jarvis::Persona::Crunchy
         init:
           alias: crunchy
           ldap_domain: websages.com
           ldap_binddn: uid=crunchy,ou=People,dc=websages,dc=com
           ldap_bindpw: ${ENV{'LDAP_PASSWORD'}}
           twitter_name: capncrunchbot
           password: ${ENV{'TWITTER_PASSWORD'}}
           retry: 300
       connectors:
         - class: Jarvis::IRC
           init:
             alias: irc_client
             nickname: crunchy
             ircname: "Cap'n Crunchbot"
             server: 127.0.0.1
             domain: websages.com
             channel_list:
               - #soggies
             persona: crunchy
     - name: berry
       persona:
         class: Jarvis::Persona::Crunchy
         init:
           alias: beta
           ldap_domain: websages.com
           ldap_binddn: uid=crunchy,ou=People,dc=websages,dc=com
           ldap_bindpw: ${ENV{'LDAP_PASSWORD'}}
           twitter_name: capncrunchbot
           password: ${ENV{'TWITTER_PASSWORD'}}
           retry: 300
       connectors:
         - class: Jarvis::IRC
           init:
             alias: beta_irc
             nickname: beta
             ircname: "beta Cap'n Crunchbot"
             server: 127.0.0.1
             domain: websages.com
             channel_list:
               - #puppies
             persona: beta
    ...
}
    
sub must {
    my $self = shift;
    return  [ ];
}

sub may {
    my $self = shift;
    return  { 'brainpath' => '/dev/shm/brain/system' };
}

sub persona_start{
    my $self=shift;
    my @brainpath = split('/',$self->{'brainpath'}); 
    shift(@brainpath); # remove the null in [0]
    # mkdir -p
    my $bpath="";
    while(my $append = shift(@brainpath)){
        $bpath = $bpath.'/'.$append;
        if(! -d $bpath ){ mkdir($bpath); }
    }
    if(! -f $self->{'brainpath'}."/megahal.trn"){ 
        my $agent = LWP::UserAgent->new();
        $agent->agent( 'Mozilla/5.0' );
        my $response = $agent->get("http://github.com/cjg/megahal/raw/master/data/megahal.trn");
        if ( $response->content ne '0' ) {
            my $fh = FileHandle->new("> $self->{'brainpath'}/megahal.trn");
            if (defined $fh) {
                print $fh $response->content;
                $fh->close;
            }
        }
    }
    $self->{'megahal'} = new AI::MegaHAL(
                                          'Path'     => $self->{'brainpath'},
                                          'Banner'   => 0,
                                          'Prompt'   => 0,
                                          'Wrap'     => 0,
                                          'AutoSave' => 1
                                        );
    $self->known_personas();
    return $self;
}

sub input{
    my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    # un-wrap the $msg
    my ( $sender_alias, $respond_event, $who, $where, $what, $id ) =
       ( 
         $msg->{'sender_alias'},
         $msg->{'reply_event'},
         $msg->{'conversation'}->{'nick'},
         $msg->{'conversation'}->{'room'},
         $msg->{'conversation'}->{'body'},
         $msg->{'conversation'}->{'id'},
       );
    my $direct=$msg->{'conversation'}->{'direct'}||0;
    if(defined($what)){
        if(defined($heap->{'locations'}->{$sender_alias}->{$where})){
            foreach my $chan_nick (@{ $heap->{'locations'}->{$sender_alias}->{$where} }){
                if($what=~m/^\s*$chan_nick\s*:*\s*/){
                    $what=~s/^\s*$chan_nick\s*:*\s*//;
                    $direct=1;
                }
            }
        }
        my $replies=[];
        ########################################################################
        #                                                                      #
        ########################################################################
        for ( $what ) {
            /^\s*!*help\s*/          && do { $replies = [ "i need a help routine" ] if($direct); last; };
            /^\s*!*spawn\s*(.*)/     && do { $replies = [ $self->spawn($1) ] if($direct); last;};
            /^\s*!*terminate\s*(.*)/ && do { $replies = [ $self->terminate($1) ] if($direct); last;};
            /.*/                     && do { $replies = [ "i don't understand"    ] if($direct); last; };
            /.*/                     && do { last; }
        }
        ########################################################################
        #                                                                      #
        ########################################################################
        if($direct==1){
            foreach my $line (@{ $replies }){
                if($msg->{'conversation'}->{'direct'} == 0){
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $who.': '.$line); }
                }else{
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $line); }
                }
            }
        }else{
            foreach my $line (@{ $replies }){
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $line); }
            }
        }
    }
    return $self->{'alias'};
}

sub spawn{
    my $self=shift;
    my $persona = shift if @_;
    $persona=~s/^\s+//;
    my $found=0;
    foreach my $p (@{ $persona }){
        if(defined($self->{'known_personas'}->{$persona})){
            if($p->{'name'} eq $persona){
                my $poe = new POE::Builder({ 'debug' => '0','trace' => '0' });
                return undef unless $poe;
                
                push( 
                     @{ $self->{$persona} }, 
                     $poe->object_session( $p->{'persona'}->{'class'}->new( $p->{'persona'}->{'init'} ) ); 
                );
                foreach my $conn (@{ $p->{'connectors'} }){
                    push( 
                         @{ $self->{$persona} }, 
                         $poe->object_session( $conn->{'class'}->new( $conn->{'init'} ) ); 
                    );
                }
                print Data::Dumper->Dump([$self->{$persona}]);
                return "$persona spawned."
            }
        }
    }
    return "I don't know how to become $persona." if(!$found);
}

# As long as the yaml lines up with itself, 
# you can indent as much as you want to keep the here statements pretty
sub indented_yaml{
     my $self = shift;
     my $iyaml = shift if @_;
     return undef unless $iyaml;
     my @lines = split('\n', $iyaml);
     my $min_indent=-1;
     foreach my $line (@lines){   
         my @chars = split('',$line);
         my $spcidx=0;
         foreach my $char (@chars){
             if($char eq ' '){
                 $spcidx++;
             }else{
                 if(($min_indent == -1) || ($min_indent > $spcidx)){
                     $min_indent=$spcidx;
                 }
             }
         }
     }
     foreach my $line (@lines){
         $line=~s/ {$min_indent}//;
     }
     my $yaml=join("\n",@lines)."\n";
     return YAML::Load($yaml);
}


1;
