using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace MvcMusicStore.Models
{
    [Table("orderdetails", Schema = "mvcmusicstore_mvcmusicstore_dbo")]
    public class OrderDetail
    {
        [Key]
        [Column("orderdetailid")]
        public int OrderDetailId { get; set; }

        [Column("orderid")]
        public int OrderId { get; set; }

        [Column("albumid")]
        public int AlbumId { get; set; }

        [Column("quantity")]
        public int Quantity { get; set; }

        [Column("unitprice")]
        public decimal UnitPrice { get; set; }

        public virtual Album Album { get; set; }
        public virtual Order Order { get; set; }
    }
}