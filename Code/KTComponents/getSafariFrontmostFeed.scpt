FasdUAS 1.101.10   ��   ��    k             l    T ��  O     T  	  Z    S 
 ���� 
 I   �� ��
�� .coredoexbool       obj   4    �� 
�� 
docu  m    ���� ��    Z    O  ����  I   �� ��
�� .coredoexbool       obj   l    ��  n        1    ��
�� 
pURL  l    ��  4   �� 
�� 
docu  m    ���� ��  ��  ��    k    K       l   �� ��    F @ based on http://bbs.applescript.net/viewtopic.php?id=15811					         r        m      ��

for(i=0;i<document.getElementsByTagName('link').length;i++){
with (document.getElementsByTagName("link").item(i)){
if (rel == 'alternate' && type.indexOf('application/') == 0 && type.indexOf('+xml') == (type.length - 4)) {
   return absURL(href);
}
}
}

function absURL(u){
if (u.indexOf('://') == -1) { // relative url
if (u.indexOf('/') == 0) { // eg, '/blah.xml' or '/blah/blah.xml'
   return window.location.host + u;
} else if (u.indexOf('../' == 0)) { // eg, '../blah.xml' or '../../../../blah.xml'
   u = u.split('../'); d = d.split('/'); nu = [];
   d = window.location.href.substring(0,window.location.href.lastIndexOf('/'));
   for(x=0;x<d.length-u.length+1;x++)nu.push(d[x]);
   return nu.join('/') + '/' + u[u.length-1];
} else { // eg, 'blah/blah.xml' or 'blah/blah/blah.xml'
   d = window.location.href.substring(0,window.location.href.lastIndexOf('/'));
   return d + '/' + u;
}
} else {
return u;
}
}

     o      ���� 0 x         l     ������  ��      ! " ! r     , # $ # l    * %�� % I    *�� & '
�� .sfridojsnull���    obj  & o     !���� 0 x   ' �� (��
�� 
dcnm ( 4   " &�� )
�� 
docu ) m   $ %���� ��  ��   $ o      ���� 0 thefeed theFeed "  * + * r   - 5 , - , l  - 3 .�� . n   - 3 / 0 / 1   1 3��
�� 
pURL 0 l  - 1 1�� 1 4  - 1�� 2
�� 
docu 2 m   / 0���� ��  ��   - o      ���� 0 theurl theURL +  3 4 3 r   6 > 5 6 5 l  6 < 7�� 7 n   6 < 8 9 8 1   : <��
�� 
pnam 9 4  6 :�� :
�� 
docu : m   8 9���� ��   6 o      ���� 0 thetitle theTitle 4  ; < ; r   ? H = > = c   ? F ? @ ? J   ? D A A  B C B o   ? @���� 0 thefeed theFeed C  D E D o   @ A���� 0 theurl theURL E  F�� F o   A B���� 0 thetitle theTitle��   @ m   D E��
�� 
list > o      ���� 0 thelist theList <  G�� G L   I K H H o   I J���� 0 thelist theList��  ��  ��  ��  ��   	 m      I I�null     ߀��  K
Safari.appMȐ4���@  ����)Q �    ���������G͐    @   @   �e   sfri   alis    8  Tiger                      ���]H+    K
Safari.app                                                      d �1�S        ����  	                Applications    ���]      �1�S      K  Tiger:Applications:Safari.app    
 S a f a r i . a p p    T i g e r  Applications/Safari.app   / ��  ��     J�� J l     ������  ��  ��       �� K L��   K ��
�� .aevtoappnull  �   � **** L �� M���� N O��
�� .aevtoappnull  �   � **** M k     T P P  ����  ��  ��   N   O  I������ ������������������
�� 
docu
�� .coredoexbool       obj 
�� 
pURL�� 0 x  
�� 
dcnm
�� .sfridojsnull���    obj �� 0 thefeed theFeed�� 0 theurl theURL
�� 
pnam�� 0 thetitle theTitle
�� 
list�� 0 thelist theList�� U� Q*�k/j  E*�k/�,j  4�E�O��*�k/l E�O*�k/�,E�O*�k/�,E�O���mv�&E�O�Y hY hUascr  ��ޭ